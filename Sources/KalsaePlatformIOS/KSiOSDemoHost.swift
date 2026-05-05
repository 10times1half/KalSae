#if os(iOS)
    internal import UIKit
    public import KalsaeCore
    public import Foundation

    /// iOS 플랫폼에서 사용하는 단일 윈도우 호스트. `KSApp`이 부팅
    /// 로직을 공유할 수 있도록 `KSMacDemoHost`와 유사하게 설계된다.
    ///
    /// 라이프사이클:
    /// 1. `KSApp.boot(...)`이 `init(windowConfig:registry:)`를 호출해
    ///    윈도우가 나타나기 전에 스크립트/에셋루트를 첨부할 수 있도록 `WKWebView`를 즉시 생성한다.
    /// 2. `KSApp`이 `addDocumentCreatedScript`, `setAssetRoot`, `start`를 호출한다.
    ///    `start`에서 받은 URL은 `_pendingURL`로 저장된다.
    /// 3. `KSApp.run()` → `runMessageLoop()`이 `KSiOSRuntime`에 `self`를 저장하고
    ///    `UIApplicationMain`에 제어를 넘기다.
    /// 4. `KSiOSAppDelegate.didFinishLaunching`이 런타임에서 호스트를 불러와
    ///    `UIWindow` + `KSiOSWebViewController`를 생성하고 `onWindowReady`를 호출해
    ///    탐색을 트리거한다.
    @MainActor
    public final class KSiOSDemoHost {
        public let registry: KSCommandRegistry

        let windowConfig: KSWindowConfig  // 패키지 내부 — KSiOSAppDelegate가 읽음
        let webViewHost: KSiOSWebViewHost  // 패키지 내부 — KSiOSAppDelegate가 읽음
        private let bridge: KSiOSBridge

        private var _mainHandle: KSWindowHandle
        private var _pendingURL: String?
        private var _pendingDevtools: Bool = false

        public init(
            windowConfig: KSWindowConfig,
            registry: KSCommandRegistry
        ) throws(KSError) {
            self.registry = registry
            self.windowConfig = windowConfig
            // `KSWindowConfig.transparent`는 Windows 전용 (v0.3 시점).
            // iOS 백엔드는 1회 경고 로그를 남기고 무시한다.
            if windowConfig.transparent {
                Self.warnTransparentOnce()
            }
            // KSiOSHandleRegistry에 등록해 KSiOSWindowBackend.find(label:)에서 찾을 수 있게 한다.
            self._mainHandle = KSiOSHandleRegistry.shared.register(label: windowConfig.label)
            self.webViewHost = KSiOSWebViewHost(label: windowConfig.label)
            self.bridge = KSiOSBridge(host: webViewHost, registry: registry, windowLabel: windowConfig.label)
            try self.bridge.install()
        }

        public var mainHandle: KSWindowHandle { _mainHandle }

        public func addDocumentCreatedScript(_ script: String) throws(KSError) {
            try webViewHost.addDocumentCreatedScript(script)
        }

        public func setAssetRoot(_ root: URL) throws(KSError) {
            try webViewHost.setAssetRoot(root)
        }

        /// 자산 응답에 Cross-Origin Isolation 헤더(COOP/COEP/CORP) 자동 추가 여부를
        /// 토글한다. `KSSecurityConfig.crossOriginIsolation`에 대응한다.
        public func setCrossOriginIsolation(_ enabled: Bool) {
            webViewHost.setCrossOriginIsolation(enabled)
        }

        /// URL을 저장한다; 실제 탐색은 `UIWindow`이 존재하면
        /// `onWindowReady`에서 실행된다.
        public func start(url: String, devtools: Bool) throws(KSError) {
            _pendingURL = url
            _pendingDevtools = devtools
        }

        /// `KSiOSAppDelegate`가 `UIWindow`이 화면에 표시된 후 호출한다.
        func onWindowReady(viewController: KSiOSWebViewController) {
            _ = viewController
            // KSiOSWindowBackend.webView(for:)가 해석할 수 있도록 웹뷰 호스트를 등록한다.
            KSiOSHandleRegistry.shared.registerWebView(webViewHost, for: windowConfig.label)
            if let url = _pendingURL {
                do {
                    try webViewHost.navigate(url: url)
                } catch {
                    KSLog.logger("platform.ios.demohost")
                        .error("navigate failed: \(error)")
                }
            }
            if _pendingDevtools {
                try? webViewHost.openDevTools()
            }
        }

        public func emit(_ event: String, payload: any Encodable) throws(KSError) {
            try bridge.emit(event: event, payload: payload)
        }

        /// 현재 문서를 다시 로드한다. dev 라이브 리로드 호환용 — iOS에서는
        /// 실제 빌드/배포 사이클이 다르므로 데스크톱 빌드와 코드 호환을 위한
        /// 표면만 제공한다 (no-op).
        public func reload() {
            // no-op: iOS에는 dev watch 시나리오가 없다.
        }

        /// `self`를 `KSiOSRuntime`에 저장하고 `UIApplicationMain`을 통해
        /// UIKit 이벤트 루프를 시작한다. 이 함수는 돌아오지 않는다.
        public func runMessageLoop() -> Int32 {
            KSiOSRuntime.shared.pendingDemoHost = self
            UIApplicationMain(
                CommandLine.argc,
                CommandLine.unsafeArgv,
                nil,
                NSStringFromClass(KSiOSAppDelegate.self))
            return 0
        }

        nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
            Task { @MainActor in block() }
        }

        /// iOS는 프로그래맰력 종료를 위한 공개 API가 없다.
        nonisolated public func requestQuit() {}

        public func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?) {
            // iOS에는 윈도우 닫기 개념이 없다.
            _ = cb
        }

        public func setOnSuspend(_ cb: (@MainActor () -> Void)?) {
            KSiOSLifecycleRelay.shared.onSuspend = cb
        }

        public func setOnResume(_ cb: (@MainActor () -> Void)?) {
            KSiOSLifecycleRelay.shared.onResume = cb
        }

        public func setWindowStateSaveSink(
            _ sink: (@MainActor (KSPersistedWindowState) -> Void)?
        ) {
            _ = sink
        }

        /// JS `__ks.*` 내장 명령을 레지스트리에 등록한다.
        ///
        /// `KSApp.boot()` 내부에서 자동으로 호출된다. 직접 호출할 경우
        /// `start(url:devtools:)` 이전에 실행해야 한다.
        public func registerBuiltinCommands(
            platformName: String = "iOS (UIKit + WKWebView)",
            shellScope: KSShellScope = .init(),
            notificationScope: KSNotificationScope = .init(),
            fsScope: KSFSScope = .init(),
            httpScope: KSHTTPScope = .init(),
            autostart: (any KSAutostartBackend)? = nil,
            deepLink: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = nil,
            appDirectory: URL? = nil
        ) async {
            let cachedHandle = _mainHandle
            let mainProvider: @Sendable () -> KSWindowHandle? = { cachedHandle }
            let quitBlock: @Sendable () -> Void = { [weak self] in self?.requestQuit() }
            await KSBuiltinCommands.register(
                into: registry,
                windows: KSiOSWindowBackend(),
                shell: KSiOSShellBackend(),
                clipboard: KSiOSClipboardBackend(),
                notifications: KSiOSNotificationBackend(),
                dialogs: KSiOSDialogBackend(),
                mainWindow: mainProvider,
                quit: quitBlock,
                platformName: platformName,
                shellScope: shellScope,
                notificationScope: notificationScope,
                fsScope: fsScope,
                httpScope: httpScope,
                autostart: autostart,
                deepLink: deepLink,
                appDirectory: appDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        }

        // MARK: - 미구현 옵션 1회 경고

        nonisolated(unsafe) private static var didWarnTransparent = false
        nonisolated(unsafe) private static let warnLock = NSLock()

        fileprivate static func warnTransparentOnce() {
            warnLock.lock()
            defer { warnLock.unlock() }
            guard !didWarnTransparent else { return }
            didWarnTransparent = true
            KSLog.logger("platform.ios.demohost").warning(
                "KSWindowConfig.transparent=true 는 iOS에서 아직 지원되지 않습니다 (Windows 전용, v0.3). 무시됩니다."
            )
        }
    }
#endif
