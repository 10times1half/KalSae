#if os(iOS)
    public import KalsaeCore
    public import Foundation
    internal import UIKit

    /// `KSMenuBackend`의 iOS 구현체입니다.
    ///
    /// iOS는 단일 `UIScene` 모델이라 데스크톱식 영구 메뉴바가 없으므로
    /// `installAppMenu` / `installWindowMenu`는 의도적으로 no-op입니다
    /// (Android의 단일 Activity 모델과 동일 — 5-OS 통합 부팅 흐름이 동일한
    /// 코드로 동작하도록 설계상 throw 대신 silent no-op + 1회 경고 로그로
    /// 처리합니다).
    ///
    /// `showContextMenu`만 의미 있는 작업을 수행하며, `UIAlertController`의
    /// actionSheet 스타일로 컨텍스트 메뉴를 표시합니다.
    ///
    /// 사용자가 메뉴 항목을 선택하면 해당 항목의 `command`가
    /// `KSiOSCommandRouter.shared`로 디스패치되어 macOS / Windows / Linux /
    /// Android와 동일한 라우팅 표면을 갖습니다.
    ///
    /// - Note: `@unchecked Sendable` — `NSLock`으로 상태 보호 + UIKit 메인
    ///   스레드 어피니티로 인해 액터보다 `NSLock`이 적합합니다.
    // @unchecked: NSLock + UIKit 메인 스레드 어피니티 — actor 부적합
    public final class KSiOSMenuBackend: KSMenuBackend, @unchecked Sendable {
        private let lock = NSLock()
        private var _appMenuWarned: Bool = false
        private var _windowMenuWarned: Bool = false

        public init() {}

        /// iOS에는 영구 애플리케이션 메뉴바가 없으므로 의도적으로 no-op입니다.
        /// 첫 호출 시 1회 경고 로그를 남겨 호스트가 의도치 않게 메뉴를
        /// 기대하는 경우를 디버깅할 수 있게 합니다.
        /// - Parameter items: 메뉴 항목 배열 (iOS에서 무시됨)
        /// - Throws: 오류를 던지지 않음 (Android와 동일한 silent no-op 정책)
        public func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) {
            _ = items
            let shouldWarn = lock.withLock { () -> Bool in
                if _appMenuWarned { return false }
                _appMenuWarned = true
                return true
            }
            if shouldWarn {
                KSLog.logger("platform.ios.menu").warning(
                    "installAppMenu is a no-op on iOS — no persistent application menu bar.")
            }
        }

        /// iOS의 단일 씬 모델에서는 창별 메뉴바가 존재하지 않으므로
        /// 의도적으로 no-op입니다. 첫 호출 시 1회 경고 로그를 남깁니다.
        /// - Parameters:
        ///   - handle: 대상 윈도우 핸들 (iOS에서 무시됨)
        ///   - items: 메뉴 항목 배열 (iOS에서 무시됨)
        /// - Throws: 오류를 던지지 않음 (Android와 동일한 silent no-op 정책)
        public func installWindowMenu(
            _ handle: KSWindowHandle,
            items: [KSMenuItem]
        ) async throws(KSError) {
            _ = (handle, items)
            let shouldWarn = lock.withLock { () -> Bool in
                if _windowMenuWarned { return false }
                _windowMenuWarned = true
                return true
            }
            if shouldWarn {
                KSLog.logger("platform.ios.menu").warning(
                    "installWindowMenu is a no-op on iOS — no per-window menu bar.")
            }
        }

        /// 등록된 webView/window 위에 `UIAlertController(.actionSheet)`를
        /// 표시하여 컨텍스트 메뉴를 보여줍니다.
        ///
        /// 액션 항목(`kind == .action`)만 노출하며, 서브메뉴와 구분선은
        /// 무시됩니다. 사용자가 선택한 항목의 `command`는
        /// `KSiOSCommandRouter.shared`로 디스패치됩니다.
        ///
        /// iPad에서는 actionSheet가 popover anchor를 필요로 하므로 `point`를
        /// source rect로 사용합니다. 부모 뷰 컨트롤러를 찾을 수 없으면
        /// 조용히 종료됩니다(호스트가 KSiOSDemoHost 부팅을 마치기 전에
        /// 호출된 경우 — Android와 동일한 default-deny 정책).
        ///
        /// - Parameters:
        ///   - items: 메뉴 항목 배열
        ///   - point: 컨텍스트 메뉴를 표시할 화면 좌표
        ///   - handle: 대상 윈도우 핸들 (선택 사항)
        /// - Throws: 항목이 없거나 부모 뷰 컨트롤러를 찾을 수 없어도 오류를
        ///   던지지 않음
        public func showContextMenu(
            _ items: [KSMenuItem],
            at point: KSPoint,
            in handle: KSWindowHandle?
        ) async throws(KSError) {
            let flat = items.filter { $0.kind == .action }
            guard !flat.isEmpty else { return }

            await MainActor.run {
                guard let host = KSiOSDialogPresenter.parentVC(for: handle) else {
                    KSLog.logger("platform.ios.menu").warning(
                        "showContextMenu: no parent UIViewController — dropping.")
                    return
                }
                let alert = UIAlertController(
                    title: nil, message: nil, preferredStyle: .actionSheet)
                for item in flat {
                    let label = item.label ?? item.id ?? "(action)"
                    let action = UIAlertAction(
                        title: label,
                        style: .default
                    ) { _ in
                        if let command = item.command {
                            KSiOSCommandRouter.shared.dispatch(
                                command: command, itemID: item.id)
                        }
                    }
                    action.isEnabled = item.enabled
                    alert.addAction(action)
                }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

                // iPad: actionSheet는 popover anchor가 필수입니다.
                // anchor가 없으면 크래시가 발생하므로 sourceRect를 설정합니다.
                if let popover = alert.popoverPresentationController {
                    popover.sourceView = host.view
                    popover.sourceRect = CGRect(
                        x: point.x, y: point.y, width: 1, height: 1)
                    popover.permittedArrowDirections = []
                }
                host.present(alert, animated: true)
            }
        }
    }
#endif
