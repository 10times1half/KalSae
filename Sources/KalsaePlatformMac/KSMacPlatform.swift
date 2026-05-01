#if os(macOS)
internal import AppKit
internal import Darwin
public import KalsaeCore
public import Foundation

/// macOS 플랫폼 백엔드 (AppKit + WKWebView). Phase 2 구현:
/// `WKWebView`에 대한 Phase 1의 IPC 계약을 검증할 수 있는
/// 기본 기능을 부팅한다. 전체 PAL 커버리지(다이얼로그, 트레이, 메뉴, 알림)는
/// 이후 단계에서 추가될 예정이다.
public final class KSMacPlatform: KSPlatform, @unchecked Sendable {
    public var name: String { "macOS (AppKit + WKWebView)" }

    public let commandRegistry: KSCommandRegistry

    public var windows: any KSWindowBackend { _windows }
    public var dialogs: any KSDialogBackend { _dialogs }
    public var tray: (any KSTrayBackend)? { _tray }
    public var menus: any KSMenuBackend { _menus }
    public var notifications: any KSNotificationBackend { _notifications }
    public var shell: (any KSShellBackend)? { _shell }
    public var clipboard: (any KSClipboardBackend)? { _clipboard }
    public var accelerators: (any KSAcceleratorBackend)? { _accelerators }
    public var autostart: (any KSAutostartBackend)? { _autostart }
    public var deepLink: (any KSDeepLinkBackend)? { _deepLink }

    private let _windows: KSMacWindowBackend
    private let _dialogs: KSMacDialogBackend
    private let _tray: KSMacTrayBackend
    private let _menus: KSMacMenuBackend
    private let _notifications: KSMacNotificationBackend
    private let _shell: KSMacShellBackend
    private let _clipboard: KSMacClipboardBackend
    private nonisolated(unsafe) var _accelerators: KSMacAcceleratorBackend?
    // run(config:configure:) 중에 설정됨. @unchecked Sendable 계약으로 보호.
    private nonisolated(unsafe) var _autostart: (any KSAutostartBackend)?
    private nonisolated(unsafe) var _deepLink: (any KSDeepLinkBackend)?

    public init() {
        let registry = KSCommandRegistry()
        self.commandRegistry = registry
        self._windows = KSMacWindowBackend()
        self._dialogs = KSMacDialogBackend()
        self._tray = KSMacTrayBackend()
        self._menus = KSMacMenuBackend()
        self._notifications = KSMacNotificationBackend()
        self._shell = KSMacShellBackend()
        self._clipboard = KSMacClipboardBackend()
        self._accelerators = nil
    }

    public func run(
        config: KSConfig,
        configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
    ) async throws(KSError) -> Never {
        let code = try await runOnMain(config: config, configure: configure)
        Darwin.exit(Int32(code))
        fatalError("unreachable")
    }

    @MainActor
    private func runOnMain(
        config: KSConfig,
        configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
    ) async throws(KSError) -> Int32 {
        if _accelerators == nil {
            _accelerators = KSMacAcceleratorBackend()
        }

        let window = try Self.selectWindow(from: config)

        await commandRegistry.setAllowlist(config.security.commandAllowlist)
        await commandRegistry.setRateLimit(config.security.commandRateLimit)

        let stateStore: KSWindowStateStore? = window.persistState
            ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
            : nil

        let host = try KSMacDemoHost(
            windowConfig: window,
            registry: commandRegistry)

        if let store = stateStore {
            let label = window.label
            host.setWindowStateSaveSink { state in
                _ = store.save(label: label, state: state)
            }
        }

        let resourceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(config.build.frontendDist)
        let servingMode = Self.decideServingMode(
            windowURL: window.url,
            devServerURL: config.build.devServerURL,
            resourceRoot: resourceRoot)

        if case .virtualHost(let servedRoot) = servingMode {
            try host.setAssetRoot(servedRoot)
        }

        try host.addDocumentCreatedScript(Self.cspInjectionScript(config.security.csp))

        if config.security.contextMenu == .disabled {
            host.setDefaultContextMenusEnabled(false)
        }
        if !config.security.allowExternalDrop {
            host.setAllowExternalDrop(false)
        }

        let url = Self.resolveStartURL(
            windowURL: window.url,
            devServerURL: config.build.devServerURL,
            servingMode: servingMode)
        // 보안: 릴리스 빌드에서는 설정값에 무관하게 개발자 도구가 강제 비활성화된다.
        // AGENTS §5 + 감사 결과 #8 참조.
        #if DEBUG
        let effectiveDevtools = config.security.devtools
        #else
        let effectiveDevtools = false
        #endif
        try host.startPrepared(url: url, devtools: effectiveDevtools)

        if let appMenu = config.menu?.appMenu {
            try await _menus.installAppMenu(appMenu)
        }
        if let windowMenu = config.menu?.windowMenu,
           let mainHandle = host.mainHandle {
            try await _menus.installWindowMenu(mainHandle, items: windowMenu)
        }
        if let trayConfig = config.tray {
            try await _tray.install(trayConfig)
        }

        KSMacCommandRouter.shared.clear()
        KSMacCommandRouter.shared.subscribe { [weak host] command, itemID in
            guard let host else { return }
            struct MenuClickPayload: Encodable {
                let command: String
                let itemID: String?
            }
            try? host.emit("menu", payload: MenuClickPayload(command: command, itemID: itemID))
            let registry = self.commandRegistry
            Task.detached {
                _ = await registry.dispatch(name: command, args: Data("{}".utf8))
            }
        }

        let autostartBackend: (any KSAutostartBackend)? = config.autostart.map { _ in
            KSMacAutostartBackend()
        }
        let deepLinkPair: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = {
            guard let dlc = config.deepLink else { return nil }
            KSMacDeepLinkBackend.installAppleEventHandler()
            let backend = KSMacDeepLinkBackend(identifier: config.app.identifier)
            if dlc.autoRegisterOnLaunch {
                for s in dlc.schemes {
                    try? backend.register(scheme: s)
                }
            }
            return (backend, dlc)
        }()
        _autostart = autostartBackend
        _deepLink = deepLinkPair?.backend
        let mainHandle = host.mainHandle

        await KSBuiltinCommands.register(
            into: commandRegistry,
            windows: _windows,
            shell: _shell,
            clipboard: _clipboard,
            notifications: _notifications,
            dialogs: _dialogs,
            mainWindow: { mainHandle },
            quit: { [weak host] in host?.requestQuit() },
            platformName: name,
            shellScope: config.security.shell,
            notificationScope: config.security.notifications,
            fsScope: config.security.fs,
            httpScope: config.security.http,
            autostart: autostartBackend,
            deepLink: deepLinkPair,
            appDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

        try await configure(self)

        return host.runMessageLoop()
    }
}

private extension KSMacPlatform {
    enum ServingMode: Sendable {
        case virtualHost(URL)
        case devServer
        case fallback
    }

    static func selectWindow(from config: KSConfig) throws(KSError) -> KSWindowConfig {
        guard let first = config.windows.first else {
            throw KSError.configInvalid("config.windows is empty")
        }
        return first
    }

    static func decideServingMode(
        windowURL: String?,
        devServerURL: String,
        resourceRoot: URL
    ) -> ServingMode {
        let devIsRemote = isRemoteURL(devServerURL)
        if windowURL == nil, devIsRemote {
            return .devServer
        }
        if isDirectory(resourceRoot) {
            return .virtualHost(resourceRoot)
        }
        return .fallback
    }

    static func resolveStartURL(
        windowURL: String?,
        devServerURL: String,
        servingMode: ServingMode
    ) -> String {
        if let windowURL { return windowURL }
        switch servingMode {
        case .virtualHost:
            return "ks://app/index.html"
        case .devServer, .fallback:
            return devServerURL
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    static func isRemoteURL(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.lowercased() == "about:blank" { return false }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    static func cspInjectionScript(_ csp: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(csp.count + 8)
        for ch in csp {
            switch ch {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            default: escaped.append(ch)
            }
        }
        return """
        (function(){
                    var csp = "\(escaped)";
          function install() {
            if (!document.head && document.documentElement) {
              var h = document.createElement('head');
              document.documentElement.insertBefore(h, document.documentElement.firstChild);
            }
            if (!document.head) { return false; }
            var meta = document.createElement('meta');
            meta.httpEquiv = 'Content-Security-Policy';
            meta.content = csp;
            document.head.insertBefore(meta, document.head.firstChild);
            return true;
          }
          if (!install()) {
            var obs = new MutationObserver(function(_, o){
              if (install()) { o.disconnect(); }
            });
            obs.observe(document, {childList:true, subtree:true});
          }
        })();
        """
    }
}

// MARK: - Phase 2 데모 호스트

/// Phase 2 데모 실행 파일에서 사용하는 단일 윈도우 호스트.
/// `KalsaeDemo` 타겟이 명령 등록 로직을 공유할 수 있도록
/// `KSWindowsDemoHost`와 동일하게 설계되었다.
@MainActor
public final class KSMacDemoHost {
    public let registry: KSCommandRegistry
    nonisolated private let window: KSMacWindow
    private let webview: WKWebViewHost
    public let bridge: WKBridge
    private var onSuspendSwift: (@MainActor () -> Void)?
    private var onResumeSwift: (@MainActor () -> Void)?
    private var workspaceObservers: [NSObjectProtocol] = []

    public init(windowConfig: KSWindowConfig,
                registry: KSCommandRegistry) throws(KSError) {
        KSMacApp.shared.ensureInitialized()

        self.registry = registry
        self.window = try KSMacWindow(config: windowConfig)
        self.webview = WKWebViewHost(label: windowConfig.label)
        self.window.webviewHost = self.webview
        self.bridge = WKBridge(host: webview, registry: registry)
        self.installPowerObservers()

        let raw = UInt64(UInt(bitPattern: ObjectIdentifier(window)))
        KSMacHandleRegistry.shared.register(
            label: windowConfig.label,
            rawValue: raw,
            window: window)
    }

    public func start(url: String, devtools: Bool) throws(KSError) {
        window.setContentView(webview.webView)
        try bridge.install()
        try webview.navigate(url: url)
        if devtools {
            try? webview.openDevTools()
        }
    }

    public func startPrepared(url: String, devtools: Bool) throws(KSError) {
        try start(url: url, devtools: devtools)
    }

    /// `root`에서 에셋을 제공하도록 `ks://` 스킴 핸들러를 바인딩한다.
    /// macOS에서 탐색 URL은 `ks://app/index.html`이다.
    public func setAssetRoot(_ root: URL) throws(KSError) {
        try webview.setAssetRoot(root)
    }

    /// 모든 문서 시작 시 실행될 JS 스니폫을 대기열에 추가한다.
    public func addDocumentCreatedScript(_ script: String) throws(KSError) {
        try webview.addDocumentCreatedScript(script)
    }

    public func runMessageLoop() -> Int32 {
        KSMacApp.shared.runMessageLoop()
    }

    public func emit(_ event: String, payload: any Encodable) throws(KSError) {
        try bridge.emit(event: event, payload: payload)
    }

    public var mainHandle: KSWindowHandle? {
        KSMacHandleRegistry.shared.handle(for: window.config.label)
    }

    /// UI 스레드로 클로저를 전달한다. `KSWindowsDemoHost.postJob`과 API 호환.
    nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
        window.postJob(block)
    }

    /// 데모 앱의 정상 종료를 요청한다.
    nonisolated public func requestQuit() {
        window.postJob {
            NSApplication.shared.terminate(nil)
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            center.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Phase C4 라이프사이클 훅
    public func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?) {
        window.setOnBeforeClose(cb)
    }

    public func setOnSuspend(_ cb: (@MainActor () -> Void)?) {
        onSuspendSwift = cb
    }

    public func setOnResume(_ cb: (@MainActor () -> Void)?) {
        onResumeSwift = cb
    }

    public func setWindowStateSaveSink(_ sink: (@MainActor (KSPersistedWindowState) -> Void)?) {
        window.setWindowStateSaveSink(sink)
    }
    public func setDefaultContextMenusEnabled(_ enabled: Bool) { _ = enabled }
    public func setAllowExternalDrop(_ allow: Bool) { _ = allow }

    /// JS `__ks.*` 내장 명령을 레지스트리에 등록한다.
    ///
    /// `KSApp.boot()` 내부에서 자동으로 호출된다.
    public func registerBuiltinCommands(
        platformName: String = "macOS (AppKit + WKWebView)",
        shellScope: KSShellScope = .init(),
        notificationScope: KSNotificationScope = .init(),
        fsScope: KSFSScope = .init(),
        httpScope: KSHTTPScope = .init(),
        autostart: (any KSAutostartBackend)? = nil,
        deepLink: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = nil,
        appDirectory: URL? = nil
    ) async {
        let handle = mainHandle
        let mainProvider: @Sendable () -> KSWindowHandle? = { handle }
        let quitBlock: @Sendable () -> Void = { [weak self] in self?.requestQuit() }
        await KSBuiltinCommands.register(
            into: registry,
            windows: KSMacWindowBackend(),
            shell: KSMacShellBackend(),
            clipboard: KSMacClipboardBackend(),
            notifications: KSMacNotificationBackend(),
            dialogs: KSMacDialogBackend(),
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

    private func installPowerObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let sleepToken = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onSuspendSwift?()
                self?.emitSystemLifecycleEvent("__ks.system.suspend")
            }
        }
        let wakeToken = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onResumeSwift?()
                self?.emitSystemLifecycleEvent("__ks.system.resume")
            }
        }
        workspaceObservers.append(sleepToken)
        workspaceObservers.append(wakeToken)
    }

    private func emitSystemLifecycleEvent(_ name: String) {
        struct EmptyPayload: Encodable {}
        try? bridge.emit(event: name, payload: EmptyPayload())
    }
}
#endif
