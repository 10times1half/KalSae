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
            self._windows = KSMacWindowBackend(registry: registry)
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

            let window = try KSBootOrchestrator.selectWindow(from: config)

            await commandRegistry.setAllowlist(config.security.commandAllowlist)
            await commandRegistry.setRateLimit(config.security.commandRateLimit)

            let stateStore: KSWindowStateStore? =
                window.persistState
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
            let servingMode = KSBootOrchestrator.decideServingMode(
                windowURL: window.url,
                devServerURL: config.build.devServerURL,
                resourceRoot: resourceRoot)

            if case .virtualHost(let servedRoot) = servingMode {
                try host.setAssetRoot(servedRoot)
            }

            host.setCrossOriginIsolation(config.security.crossOriginIsolation)

            // dev 서버 모드에서는 `devCsp`가 있으면 그것을 주입하고,
            // 없으면 주입을 건너뛴다(→ dev 서버 자체 CSP가 적용).
            // 프로덕션 CSP는 인라인 스크립트/HMR 웹소츓과 충돌하기 쉬워 그대로 적용하지 않는다.
            let injectedCSP: String? = {
                if case .devServer = servingMode {
                    return config.security.devCsp
                }
                return config.security.csp
            }()
            if let injectedCSP {
                try host.addDocumentCreatedScript(KSBootOrchestrator.cspInjectionScript(injectedCSP))
            }

            if config.security.contextMenu == .disabled {
                host.setDefaultContextMenusEnabled(false)
            }
            if !config.security.allowExternalDrop {
                host.setAllowExternalDrop(false)
                try? host.installFileDropEmitter()
            }

            // RFC-008 §2.3: 팝업 차단 + 외부 URL 라우팅. Windows 패턴과 통일.
            let shellRef = _shell
            let allowPopups = config.security.allowPopups
            try host.installSecurityHandlers(
                allowPopups: allowPopups,
                openExternal: { urlStr in
                    guard let url = URL(string: urlStr) else { return }
                    Task.detached { try? await shellRef.openExternal(url) }
                })

            let url = KSBootOrchestrator.resolveStartURL(
                windowURL: window.url,
                devServerURL: config.build.devServerURL,
                servingMode: servingMode,
                virtualHostURL: "ks://app/index.html")
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
                let mainHandle = host.mainHandle
            {
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
                navigationScope: config.security.navigation,
                autostart: autostartBackend,
                deepLink: deepLinkPair,
                appDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

            try await configure(self)

            return host.runMessageLoop()
        }
    }

    // MARK: - Phase 2 데모 호스트

    /// Phase 2 데모 실행 파일에서 사용하는 단일 윈도우 호스트.
    /// `KalsaeDemo` 타겟이 명령 등록 로직을 공유할 수 있도록
    /// `KSWindowsDemoHost`와 동일하게 설계되었다.
    @MainActor
    public final class KSMacDemoHost: KSDemoHost {
        public let registry: KSCommandRegistry
        nonisolated private let window: KSMacWindow
        private let webview: WKWebViewHost
        public let bridge: WKBridge
        private var onSuspendSwift: (@MainActor () -> Void)?
        private var onResumeSwift: (@MainActor () -> Void)?
        private var workspaceObservers: [any NSObjectProtocol] = []

        public init(
            windowConfig: KSWindowConfig,
            registry: KSCommandRegistry
        ) throws(KSError) {
            KSMacApp.shared.ensureInitialized()

            self.registry = registry
            self.window = try KSMacWindow(config: windowConfig)
            self.webview = WKWebViewHost(label: windowConfig.label, options: windowConfig.webview)
            self.window.webviewHost = self.webview
            self.bridge = WKBridge(host: webview, registry: registry, windowLabel: windowConfig.label)
            self.installPowerObservers()

            let wLabel = windowConfig.label
            window.onWindowClosed = {
                KSWindowEmitHub.shared.unregister(label: wLabel)
                struct ClosedPayload: Encodable { let label: String }
                try? KSWindowEmitHub.shared.emit(
                    event: "__ks.window.closed",
                    payload: ClosedPayload(label: wLabel),
                    to: nil)
            }

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

        /// 자산 응답에 Cross-Origin Isolation 헤더(COOP/COEP/CORP) 자동 추가 여부를
        /// 토글한다. `KSSecurityConfig.crossOriginIsolation`에 대응한다.
        public func setCrossOriginIsolation(_ enabled: Bool) {
            webview.setCrossOriginIsolation(enabled)
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

        /// 현재 문서를 다시 로드한다. dev 라이브 리로드(`KALSAE_DEV_RELOAD=1`)
        /// 에서 사용된다.
        public func reload() {
            window.reload()
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
        // RFC-008 §2.1: 컨텍스트 메뉴 / 외부 드롭 토글을 실제 WKWebView 설정으로 위임.
        public func setDefaultContextMenusEnabled(_ enabled: Bool) {
            webview.setDefaultContextMenusEnabled(enabled)
        }
        public func setAllowExternalDrop(_ allow: Bool) {
            webview.setAllowExternalDrop(allow)
        }
        // RFC-008 §2.2: 파일 드롭 emitter 설치(현재 best-effort 경고 stub).
        public func installFileDropEmitter() throws(KSError) {
            try webview.installFileDropEmitter()
        }
        // RFC-008 §2.3: 팝업 차단 + 외부 URL 라우팅 + 권한 거부 핸들러.
        public func installSecurityHandlers(
            allowPopups: Bool,
            openExternal: (@MainActor (String) -> Void)?
        ) throws(KSError) {
            try webview.installSecurityHandlers(
                allowPopups: allowPopups, openExternal: openExternal)
        }

        /// JS `__ks.*` 내장 명령을 레지스트리에 등록한다.
        ///
        /// `KSApp.boot()` 내부에서 자동으로 호출된다.
        public func registerBuiltinCommands(
            platformName: String = "macOS (AppKit + WKWebView)",
            shellScope: KSShellScope = .init(),
            notificationScope: KSNotificationScope = .init(),
            fsScope: KSFSScope = .init(),
            httpScope: KSHTTPScope = .init(),
            navigationScope: KSNavigationScope = .init(),
            autostart: (any KSAutostartBackend)? = nil,
            deepLink: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = nil,
            appDirectory: URL? = nil,
            // RFC-008 #2.13: 플랫폼이 공유 백엔드 인스턴스를 주입할 수
            // 있도록 한다. nil이면 기존 동작 유지(새 인스턴스 생성).
            windows: (any KSWindowBackend)? = nil,
            shell: (any KSShellBackend)? = nil,
            clipboard: (any KSClipboardBackend)? = nil,
            notifications: (any KSNotificationBackend)? = nil,
            dialogs: (any KSDialogBackend)? = nil
        ) async {
            let handle = mainHandle
            let mainProvider: @Sendable () -> KSWindowHandle? = { handle }
            let quitBlock: @Sendable () -> Void = { [weak self] in self?.requestQuit() }
            await KSBuiltinCommands.register(
                into: registry,
                windows: windows ?? KSMacWindowBackend(registry: registry),
                shell: shell ?? KSMacShellBackend(),
                clipboard: clipboard ?? KSMacClipboardBackend(),
                notifications: notifications ?? KSMacNotificationBackend(),
                dialogs: dialogs ?? KSMacDialogBackend(),
                mainWindow: mainProvider,
                quit: quitBlock,
                platformName: platformName,
                shellScope: shellScope,
                notificationScope: notificationScope,
                fsScope: fsScope,
                httpScope: httpScope,
                navigationScope: navigationScope,
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
