#if os(iOS)
    internal import UIKit
    public import KalsaeCore

    /// `KSiOSDemoHost.runMessageLoop()`에 의해 연결되는 UIKit 앱 델리게이트.
    ///
    /// `KSiOSRuntime.shared.pendingDemoHost`가 `KSApp.boot(...)`에서 생성된
    /// `KSiOSDemoHost`를 운반한다. 델리게이트는 여기서 이를 읽어 `UIWindow`을 생성하고
    /// `WKWebView` 븷-콘트롤러를 설치한 후 탐색을 트리거하도록
    /// 호스트에 제어를 돌려준다.
    @MainActor
    public class KSiOSAppDelegate: UIResponder, UIApplicationDelegate {
        public var window: UIWindow?

        public func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
        ) -> Bool {
            guard let host = KSiOSRuntime.shared.pendingDemoHost else { return true }
            KSiOSRuntime.shared.pendingDemoHost = nil

            let vc = KSiOSWebViewController(webViewHost: host.webViewHost)
            let win = UIWindow(frame: UIScreen.main.bounds)
            win.rootViewController = vc
            win.makeKeyAndVisible()
            self.window = win

            host.onWindowReady(viewController: vc)
            return true
        }

        public func applicationDidEnterBackground(_ application: UIApplication) {
            KSiOSLifecycleRelay.shared.didEnterBackground()
        }

        public func applicationWillEnterForeground(_ application: UIApplication) {
            KSiOSLifecycleRelay.shared.willEnterForeground()
        }
    }

    // MARK: - 라이프사이클 릴레이

    /// UIKit 라이프사이클 이벤트를 `KSiOSDemoHost`의 suspend/resume 콜백으로
    /// 포워딩하는 싱글톤. init 후 `KSiOSDemoHost`가 등록한다.
    @MainActor
    internal final class KSiOSLifecycleRelay {
        static let shared = KSiOSLifecycleRelay()
        private init() {}

        var onSuspend: (@MainActor () -> Void)?
        var onResume: (@MainActor () -> Void)?

        func didEnterBackground() { onSuspend?() }
        func willEnterForeground() { onResume?() }
    }
#endif
