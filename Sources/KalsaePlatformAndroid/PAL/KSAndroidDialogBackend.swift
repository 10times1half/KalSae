#if os(Android)
    public import KalsaeCore
    public import Foundation

    /// `KSDialogBackend`의 Android 핸들러 주입형 구현체.
    ///
    /// Android 다이얼로그(파일 선택, 메시지 등)는 `ActivityResultLauncher`를
    /// 통해 Kotlin/JVM 쪽에서 처리해야 한다. Kotlin 호스트가 아래 핸들러를
    /// 부팅 전에 설정하면 JS `__ks.dialog.*` 명령이 해당 핸들러를 통해 동작한다.
    ///
    /// 핸들러가 설정되지 않은 경우 모든 메서드는 `.unsupportedPlatform`을 throw한다.
    // @unchecked: NSLock + JVM 스레드 어피니티 — actor 부적합
    public final class KSAndroidDialogBackend: KSDialogBackend, @unchecked Sendable {
        private let lock = NSLock()

        // MARK: - Injectable handlers (set by Kotlin host)

        public var onOpenFile: ((KSOpenFileOptions, KSWindowHandle?) async -> [URL])? {
            get { lock.withLock { _onOpenFile } }
            set { lock.withLock { _onOpenFile = newValue } }
        }
        private var _onOpenFile: ((KSOpenFileOptions, KSWindowHandle?) async -> [URL])?

        public var onSaveFile: ((KSSaveFileOptions, KSWindowHandle?) async -> URL?)? {
            get { lock.withLock { _onSaveFile } }
            set { lock.withLock { _onSaveFile = newValue } }
        }
        private var _onSaveFile: ((KSSaveFileOptions, KSWindowHandle?) async -> URL?)?

        public var onSelectFolder: ((KSSelectFolderOptions, KSWindowHandle?) async -> URL?)? {
            get { lock.withLock { _onSelectFolder } }
            set { lock.withLock { _onSelectFolder = newValue } }
        }
        private var _onSelectFolder: ((KSSelectFolderOptions, KSWindowHandle?) async -> URL?)?

        public var onMessage: ((KSMessageOptions, KSWindowHandle?) async -> KSMessageResult)? {
            get { lock.withLock { _onMessage } }
            set { lock.withLock { _onMessage = newValue } }
        }
        private var _onMessage: ((KSMessageOptions, KSWindowHandle?) async -> KSMessageResult)?

        public init() {}

        // MARK: - KSDialogBackend

        public func openFile(
            options: KSOpenFileOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> [URL] {
            guard let handler = lock.withLock({ _onOpenFile }) else {
                throw KSError.unsupportedPlatform(
                    "KSAndroidDialogBackend.openFile: Kotlin bridge not installed")
            }
            return await handler(options, parent)
        }

        public func saveFile(
            options: KSSaveFileOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> URL? {
            guard let handler = lock.withLock({ _onSaveFile }) else {
                throw KSError.unsupportedPlatform(
                    "KSAndroidDialogBackend.saveFile: Kotlin bridge not installed")
            }
            return await handler(options, parent)
        }

        public func selectFolder(
            options: KSSelectFolderOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> URL? {
            guard let handler = lock.withLock({ _onSelectFolder }) else {
                throw KSError.unsupportedPlatform(
                    "KSAndroidDialogBackend.selectFolder: Kotlin bridge not installed")
            }
            return await handler(options, parent)
        }

        @discardableResult
        public func message(
            _ options: KSMessageOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> KSMessageResult {
            guard let handler = lock.withLock({ _onMessage }) else {
                throw KSError.unsupportedPlatform(
                    "KSAndroidDialogBackend.message: Kotlin bridge not installed")
            }
            return await handler(options, parent)
        }

        // MARK: - JNI 기본 핸들러 (RFC-007 Phase 4)

        /// 등록된 JNI 훅(`_jniShowAlert` / `_jniPickFile` / `_jniSaveFile` /
        /// `_jniSelectFolder`)을 사용하는 기본 핸들러를 4 개의 다이얼로그
        /// 메서드에 자동 설치한다.
        ///
        /// 동작:
        /// 1. 옵션을 JSON 으로 직렬화.
        /// 2. `KSAndroidJNIRegistry.shared.register` 로 요청 ID 와 continuation
        ///    을 등록.
        /// 3. 매칭되는 JNI 훅을 호출하여 (id, optionsJSON) 을 Kotlin 으로 전달.
        /// 4. Kotlin 이 `KalsaeJNI.onDialogResult(id, resultJson)` 으로 응답.
        /// 5. `KS_android_on_dialog_result` 가 continuation 을 깨움.
        ///
        /// 훅이 등록되지 않았거나 인코딩이 실패한 경우, 결과는 다이얼로그가
        /// 취소된 것과 동일하게(빈 배열 / nil / `.cancel`) 처리되어 호출자가
        /// 항상 결정적인 결과를 받는다.
        ///
        /// 호스트 코드가 `dialogs.onOpenFile = ...` 식으로 명시적 핸들러를 이미
        /// 주입한 경우, 이 메서드는 그 설정을 덮어쓴다. 명시 주입을 우선하려면
        /// 이 메서드를 호출하지 말 것.
        public func installJNIDefaults() {
            self.onOpenFile = { @Sendable options, _ in
                await Self.bridgeJNICall(
                    options: options,
                    hook: { KSAndroidJNIBridge.shared.pickFile },
                    decode: Self.decodeURLArray,
                    fallback: [])
            }
            self.onSaveFile = { @Sendable options, _ in
                await Self.bridgeJNICall(
                    options: options,
                    hook: { KSAndroidJNIBridge.shared.saveFile },
                    decode: Self.decodeURL,
                    fallback: nil)
            }
            self.onSelectFolder = { @Sendable options, _ in
                await Self.bridgeJNICall(
                    options: options,
                    hook: { KSAndroidJNIBridge.shared.selectFolder },
                    decode: Self.decodeURL,
                    fallback: nil)
            }
            self.onMessage = { @Sendable options, _ in
                await Self.bridgeJNICall(
                    options: options,
                    hook: { KSAndroidJNIBridge.shared.showAlert },
                    decode: Self.decodeMessageResult,
                    fallback: .cancel)
            }
        }

        /// 공통 JNI 호출 래퍼.
        /// 옵션 인코딩 실패, 훅 미설치, 매칭 응답 부재 모두 `fallback` 으로 종료.
        private static func bridgeJNICall<Options: Encodable & Sendable, Result: Sendable>(
            options: Options,
            hook: () -> ((Int32, UnsafePointer<CChar>) -> Void)?,
            decode: @Sendable @escaping (String) -> Result?,
            fallback: Result
        ) async -> Result {
            guard let json = try? JSONEncoder().encode(options),
                let optsStr = String(data: json, encoding: .utf8),
                let fn = hook()
            else {
                return fallback
            }
            return await withCheckedContinuation { (cont: CheckedContinuation<Result, Never>) in
                let id = KSAndroidJNIRegistry.shared.register { resultJSON in
                    cont.resume(returning: decode(resultJSON) ?? fallback)
                }
                optsStr.withCString { fn(id, $0) }
            }
        }

        // MARK: - 결과 JSON 디코더

        // 결과 JSON 의 일부 구조만 디코드하면 충분하므로 작은 helper 구조체를
        // 정의해 둔다.

        private struct OpenFileResultDTO: Decodable {
            let urls: [String]?
        }

        private struct URLResultDTO: Decodable {
            let url: String?
        }

        private struct MessageResultDTO: Decodable {
            let result: KSMessageResult?
        }

        private static func decodeURLArray(_ json: String) -> [URL]? {
            guard let data = json.data(using: .utf8),
                let dto = try? JSONDecoder().decode(OpenFileResultDTO.self, from: data)
            else {
                return nil
            }
            return (dto.urls ?? []).compactMap(URL.init(string:))
        }

        private static func decodeURL(_ json: String) -> URL?? {
            // 외부 옵셔널: 디코딩 성공 여부 / 내부 옵셔널: 사용자가 취소했는지.
            guard let data = json.data(using: .utf8),
                let dto = try? JSONDecoder().decode(URLResultDTO.self, from: data)
            else {
                return nil
            }
            return .some(dto.url.flatMap(URL.init(string:)))
        }

        private static func decodeMessageResult(_ json: String) -> KSMessageResult? {
            guard let data = json.data(using: .utf8),
                let dto = try? JSONDecoder().decode(MessageResultDTO.self, from: data)
            else {
                return nil
            }
            return dto.result
        }
    }

    /// JNI 훅 함수 포인터를 다이얼로그 백엔드에서 안전하게 읽기 위한 어댑터.
    /// `_jniShowAlert` 등은 KSAndroidJNIHooks.swift 에 internal 로 선언되어
    /// 있으며 `_hooksLock` 으로 보호된다. 이 어댑터는 잠금 안에서 현재 등록된
    /// 함수 포인터를 스냅샷으로 제공한다.
    struct KSAndroidJNIBridge {
        static var shared: KSAndroidJNIBridge {
            _hooksLock.withLock {
                KSAndroidJNIBridge(
                    showAlert: _jniShowAlert,
                    pickFile: _jniPickFile,
                    saveFile: _jniSaveFile,
                    selectFolder: _jniSelectFolder,
                    showContextMenu: _jniShowContextMenu)
            }
        }

        let showAlert: KSJNIShowAlert?
        let pickFile: KSJNIPickFile?
        let saveFile: KSJNISaveFile?
        let selectFolder: KSJNISelectFolder?
        let showContextMenu: KSJNIShowContextMenu?
    }
#endif
