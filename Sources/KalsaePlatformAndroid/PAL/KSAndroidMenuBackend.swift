#if os(Android)
    public import KalsaeCore
    public import Foundation

    /// `KSMenuBackend`의 Android 핸들러 주입형 구현체.
    ///
    /// Android 의 단일 Activity 모델에는 데스크톱식의 영구 메뉴바 개념이
    /// 없으므로 `installAppMenu` / `installWindowMenu` 는 의도적으로 no-op
    /// 으로 둔다(macOS 의 메뉴바, Windows 의 HMENU 와 다르게 시스템 UI 가
    /// 존재하지 않음). `showContextMenu` 만 의미 있는 작업을 수행하며,
    /// `android.widget.PopupMenu` 를 통한 컨텍스트 메뉴를 표시한다.
    ///
    /// 컨텍스트 메뉴는 Kotlin/JVM 쪽에서 처리해야 하므로 Kotlin 호스트가 부팅
    /// 전에 `onShowContextMenu` 를 주입하거나, 부팅 시 `installJNIDefaults()`
    /// 가 등록한 기본 JNI 핸들러를 사용한다. 핸들러가 없으면 조용히 종료된다
    /// (default-deny). 사용자가 메뉴 항목을 선택하면 해당 항목의
    /// `command` 가 `KSAndroidCommandRouter.shared` 로 디스패치되어 macOS /
    /// Windows / Linux 와 동일한 라우팅 표면을 갖는다.
    // @unchecked: NSLock + JVM 스레드 어피니티 — actor 부적합
    public final class KSAndroidMenuBackend: KSMenuBackend, @unchecked Sendable {
        private let lock = NSLock()

        // MARK: - Injectable handler (set by Kotlin host or installJNIDefaults)

        /// 컨텍스트 메뉴를 표시하는 핸들러. 선택된 평면화 액션 항목의 인덱스
        /// (없으면 `nil`)를 비동기로 반환한다.
        public typealias ShowContextMenuHandler = @Sendable (
            _ items: [KSMenuItem],
            _ point: KSPoint,
            _ handle: KSWindowHandle?
        ) async -> Int?

        public var onShowContextMenu: ShowContextMenuHandler? {
            get { lock.withLock { _onShowContextMenu } }
            set { lock.withLock { _onShowContextMenu = newValue } }
        }
        private var _onShowContextMenu: ShowContextMenuHandler?

        public init() {}

        // MARK: - KSMenuBackend

        /// Android 에는 영구 애플리케이션 메뉴바가 없으므로 의도적으로 no-op.
        public func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) {
            _ = items
        }

        /// Android 의 단일 Activity 모델에서는 창별 메뉴바가 존재하지 않으므로
        /// 의도적으로 no-op.
        public func installWindowMenu(
            _ handle: KSWindowHandle,
            items: [KSMenuItem]
        ) async throws(KSError) {
            _ = (handle, items)
        }

        /// `onShowContextMenu` 핸들러가 주입되어 있으면 위임하여 컨텍스트 메뉴를
        /// 표시하고, 사용자가 선택한 항목의 `command` 를
        /// `KSAndroidCommandRouter.shared` 로 디스패치한다. 핸들러가 없으면
        /// 조용히 종료된다(`KSiOSMenuBackend` 와 달리 throw 하지 않는 이유는
        /// Android 의 PopupMenu 는 JNI 호스트가 선택적으로 활성화하는 표면이며,
        /// 호스트 없이 자동으로 throw 하면 IPC 호출이 매번 실패해 default-deny
        /// 보다 시끄러운 결과를 낳기 때문 — RFC-007 §5).
        public func showContextMenu(
            _ items: [KSMenuItem],
            at point: KSPoint,
            in handle: KSWindowHandle?
        ) async throws(KSError) {
            guard let handler = lock.withLock({ _onShowContextMenu }) else {
                return
            }
            // 평면화: PopupMenu 는 액션 항목만 노출 (RFC-007 §5 "flat menus only").
            let flat = items.filter { $0.kind == .action }
            guard let selected = await handler(flat, point, handle) else { return }
            guard selected >= 0, selected < flat.count else { return }
            let item = flat[selected]
            if let command = item.command {
                await MainActor.run {
                    KSAndroidCommandRouter.shared.dispatch(
                        command: command, itemID: item.id)
                }
            }
        }

        // MARK: - JNI 기본 핸들러 (RFC-007 Phase 4 — 안정화)

        /// 등록된 JNI 훅(`_jniShowContextMenu`)을 사용하는 기본 핸들러를
        /// `onShowContextMenu` 에 설치한다.
        ///
        /// 동작:
        /// 1. 평면화된 액션 항목을 JSON 으로 직렬화.
        /// 2. `KSAndroidJNIRegistry.shared.register` 로 요청 ID 와 continuation
        ///    을 등록.
        /// 3. `_jniShowContextMenu(id, optionsJSON, x, y)` 로 Kotlin 호출.
        /// 4. Kotlin 이 `KalsaeJNI.onContextMenuResult(id, selectedIndex)` 응답
        ///    (취소시 -1).
        /// 5. `KS_android_on_context_menu_result` 가 continuation 을 깨움.
        ///
        /// 훅이 등록되지 않았거나 인코딩이 실패한 경우, 결과는 사용자가 메뉴
        /// 영역 밖을 탭한 것과 동일하게(`nil`) 처리된다.
        ///
        /// **비파괴(D2)**: 호스트가 이미 `onShowContextMenu` 를 명시적으로
        /// 주입한 경우, 이 메서드는 아무 동작도 하지 않고 그 설정을 보존한다.
        public func installJNIDefaults() {
            lock.lock()
            let already = _onShowContextMenu != nil
            lock.unlock()
            if already { return }

            self.onShowContextMenu = { @Sendable items, point, _ in
                await Self.bridgeShowContextMenu(items: items, point: point)
            }
        }

        /// 컨텍스트 메뉴 JNI 호출 래퍼.
        /// 옵션 인코딩 실패, 훅 미설치, 매칭 응답 부재 모두 `nil` 로 종료.
        private static func bridgeShowContextMenu(
            items: [KSMenuItem],
            point: KSPoint
        ) async -> Int? {
            struct PayloadItem: Encodable {
                let label: String
                let enabled: Bool
            }
            struct Payload: Encodable {
                let items: [PayloadItem]
            }
            let payload = Payload(
                items: items.map { item in
                    PayloadItem(label: item.label ?? "", enabled: item.enabled)
                })

            guard let json = try? JSONEncoder().encode(payload),
                let optsStr = String(data: json, encoding: .utf8),
                let fn = KSAndroidJNIBridge.shared.showContextMenu
            else {
                return nil
            }

            let selected: Int = await withCheckedContinuation {
                (cont: CheckedContinuation<Int, Never>) in
                let id = KSAndroidJNIRegistry.shared.register { resultJSON in
                    cont.resume(returning: Self.decodeSelectedIndex(resultJSON) ?? -1)
                }
                optsStr.withCString { fn(id, $0, Int32(point.x), Int32(point.y)) }
            }
            return selected >= 0 ? selected : nil
        }

        // MARK: - 결과 JSON 디코더

        private struct ContextMenuResultDTO: Decodable {
            let selectedIndex: Int?
        }

        private static func decodeSelectedIndex(_ json: String) -> Int? {
            guard let data = json.data(using: .utf8),
                let dto = try? JSONDecoder().decode(ContextMenuResultDTO.self, from: data)
            else { return nil }
            return dto.selectedIndex
        }
    }
#endif
