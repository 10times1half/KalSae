#if os(iOS)
    public import KalsaeCore
    public import Foundation
    internal import UIKit

    /// `KSMenuBackend`의 iOS 구현체.
    ///
    /// iOS는 단일 `UIScene` 모델이라 데스크톱식 영구 메뉴바가 없으므로
    /// `installAppMenu` / `installWindowMenu` 는 의도적으로 no-op 이다
    /// (Android의 단일 Activity 모델과 동일 — 5-OS 통합 부팅 흐름이 동일한
    /// 코드로 동작하도록 설계상 throw 대신 silent no-op + 1회 경고 로그로 처리).
    /// `showContextMenu` 만 의미 있는 작업을 수행하며, `UIAlertController`의
    /// actionSheet 스타일로 컨텍스트 메뉴를 표시한다.
    ///
    /// 사용자가 메뉴 항목을 선택하면 해당 항목의 `command` 가
    /// `KSiOSCommandRouter.shared` 로 디스패치되어 macOS / Windows / Linux /
    /// Android 와 동일한 라우팅 표면을 갖는다.
    // @unchecked: NSLock + UIKit 메인 스레드 어피니티 — actor 부적합
    public final class KSiOSMenuBackend: KSMenuBackend, @unchecked Sendable {
        private let lock = NSLock()
        private var _appMenuWarned: Bool = false
        private var _windowMenuWarned: Bool = false

        public init() {}

        /// iOS 에는 영구 애플리케이션 메뉴바가 없으므로 의도적으로 no-op.
        /// 첫 호출 시 1회 경고 로그를 남겨 호스트가 의도치 않게 메뉴를
        /// 기대하는 경우를 디버깅할 수 있게 한다.
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

        /// iOS 의 단일 씬 모델에서는 창별 메뉴바가 존재하지 않으므로
        /// 의도적으로 no-op. 첫 호출 시 1회 경고 로그를 남긴다.
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

        /// 등록된 webView/window 위에 `UIAlertController(.actionSheet)`을 띄운다.
        /// 액션 항목만 노출하며(submenu/separator 무시), 사용자가 선택한 항목의
        /// `command` 는 `KSiOSCommandRouter.shared` 로 디스패치된다. iPad 에서는
        /// popover anchor 가 필요해 `point` 를 source rect 로 사용한다.
        ///
        /// 부모 뷰 컨트롤러를 찾을 수 없으면 조용히 종료된다 (호스트가
        /// KSiOSDemoHost 부팅을 마치기 전에 호출된 경우 — Android 와 동일한
        /// default-deny 정책).
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

                // iPad: actionSheet 는 popover anchor 가 필수.
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
