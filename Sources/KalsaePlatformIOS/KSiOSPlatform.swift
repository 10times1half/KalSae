#if os(iOS)
    internal import UIKit
    internal import Darwin
    public import KalsaeCore
    public import Foundation

    // @unchecked: UIKit main thread confinement — actor unsuitable for @UIApplicationMain binding
    public final class KSiOSPlatform: KSPlatformComponentsProvider, @unchecked Sendable {
        public var name: String { "iOS (UIKit + WKWebView)" }

        public let commandRegistry: KSCommandRegistry

        // `KSPlatform`의 10개 백엔드는 `KSPlatformComponentsProvider`가
        // `components` 위임으로 자동 제공한다. iOS는 트레이/액셀러레이터를
        // 지원하지 않으므로 nil로 노출한다.
        public var components: KSPlatformComponents {
            KSPlatformComponents(
                windows: _windows,
                dialogs: _dialogs,
                menus: _menus,
                notifications: _notifications,
                tray: nil,
                shell: _shell,
                clipboard: _clipboard,
                accelerators: nil,
                autostart: _autostart,
                deepLink: _deepLink,
                credentials: KSiOSCredentialBackend())
        }

        @MainActor public var menuCommandRouter: (any KSMenuCommandRouting)? {
            KSiOSCommandRouter.shared
        }

        private let _windows: KSiOSWindowBackend
        private let _dialogs: KSiOSDialogBackend
        private let _menus: KSiOSMenuBackend
        private let _notifications: KSiOSNotificationBackend
        private let _shell: KSiOSShellBackend
        private let _clipboard: KSiOSClipboardBackend
        private let _autostart: KSiOSAutostartBackend
        // run(config:configure:) 중에 설정됨. @unchecked Sendable 계약으로 보호.
        private nonisolated(unsafe) var _deepLink: KSiOSDeepLinkBackend

        public init() {
            self.commandRegistry = KSCommandRegistry()
            self._windows = KSiOSWindowBackend()
            self._dialogs = KSiOSDialogBackend()
            self._menus = KSiOSMenuBackend()
            self._notifications = KSiOSNotificationBackend()
            self._shell = KSiOSShellBackend()
            self._clipboard = KSiOSClipboardBackend()
            self._autostart = KSiOSAutostartBackend()
            self._deepLink = KSiOSDeepLinkBackend(
                identifier: Bundle.main.bundleIdentifier ?? "kalsae")
        }

        public func run(
            config: KSConfig,
            configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
        ) async throws(KSError) -> Never {
            _ = config
            // iOS의 UIApplication 생명주기는 UIKit이 관리하므로 Swift `run()`이
            // 메인 루프를 점유하는 데스크톱 모델과 맞지 않는다. KSApp.boot() +
            // KSiOSDemoHost를 UIKit `@main` 진입점에서 사용하는 것이 정식 경로다.
            // (Android와 동일 패턴 — RFC-006/RFC-008 #2.10)
            //
            // configure 클로저에서 `self.windows` 등 백엔드에 접근하면 실제
            // UIKit 호스트와 분리된 인스턴스를 만지는 것이므로 의도대로 동작하지
            // 않을 수 있음을 경고로 알린다.
            KSLog.logger("platform.ios").warning(
                "KSiOSPlatform.run() is permanently unsupported. The configure "
                    + "closure will execute, but backends accessed via `self` are "
                    + "decoupled from the UIKit host. Use KSApp.boot() with "
                    + "KSiOSDemoHost instead.")
            try await configure(self)
            throw KSError.unsupportedPlatform(
                "KSiOSPlatform.run() is permanently unsupported — iOS lifecycle is "
                    + "UIApplication-controlled. Use KSApp.boot() + KSiOSDemoHost "
                    + "from a UIKit @main entry point instead.")
        }

        // 과거 `runOnMain` 부팅 헬퍼는 KSApp.boot() / KSiOSDemoHost 경로로 통합되어
        // 제거되었다. iOS 부팅 흐름은 KSApp.boot() → KSiOSDemoHost.runMessageLoop()
        // → KSiOSAppDelegate가 담당한다.
    }

// MARK: - Private helpers

// 부팅 헬퍼는 `KSBootOrchestrator` (KalsaeCore)로 통합됨.
#endif
