#if os(Linux)
    internal import Glibc
    public import KalsaeCore
    public import Foundation

    /// Linux 플랫폼 백엔드 (GTK4 + WebKitGTK 6.0). Phase 3 구현:
    /// 모든 핵심 PAL 표면 (윈도우, 다이얼로그, 메뉴, 셸, 클립보드,
    /// 알림, 자동시작, 딥링크)이 동작 중이다. 트레이는 AppIndicator3이
    /// 필요하여 스터브로 남아 있다; 단일 인스턴스는 `KSLinuxSingleInstance`를 통해 노출된다.
    // @unchecked: GTK main thread confinement — actor unsuitable for OS main-loop binding
    public final class KSLinuxPlatform: KSPlatformComponentsProvider, @unchecked Sendable {
        public var name: String { "Linux (GTK4 + WebKitGTK 6.0)" }

        public let commandRegistry: KSCommandRegistry

        // `KSPlatform`의 10개 백엔드는 `KSPlatformComponentsProvider`가
        // `components` 위임으로 자동 제공한다.
        public var components: KSPlatformComponents {
            KSPlatformComponents(
                windows: _windows,
                dialogs: _dialogs,
                menus: _menus,
                notifications: _notifications,
                tray: _tray,
                shell: _shell,
                clipboard: _clipboard,
                accelerators: _accelerators,
                autostart: _autostart,
                deepLink: _deepLink)
        }

        private let _windows: KSLinuxWindowBackend
        private let _dialogs: KSLinuxDialogBackend
        private let _tray: KSLinuxTrayBackend
        private let _menus: KSLinuxMenuBackend
        private let _notifications: KSLinuxNotificationBackend
        private let _shell: KSLinuxShellBackend
        private let _clipboard: KSLinuxClipboardBackend
        private let _accelerators: KSLinuxAcceleratorBackend
        // run(config:configure:) 중에 설정됨. @unchecked Sendable 계약으로 보호.
        private nonisolated(unsafe) var _autostart: (any KSAutostartBackend)?
        private nonisolated(unsafe) var _deepLink: (any KSDeepLinkBackend)?

        public init() {
            self.commandRegistry = KSCommandRegistry()
            self._windows = KSLinuxWindowBackend()
            self._dialogs = KSLinuxDialogBackend()
            self._tray = KSLinuxTrayBackend()
            self._menus = KSLinuxMenuBackend()
            self._notifications = KSLinuxNotificationBackend()
            self._shell = KSLinuxShellBackend()
            self._clipboard = KSLinuxClipboardBackend()
            self._accelerators = KSLinuxAcceleratorBackend()
        }

        public func run(
            config: KSConfig,
            configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
        ) async throws(KSError) -> Never {
            let code = try await runOnMain(config: config, configure: configure)
            Glibc.exit(Int32(code))
            fatalError("unreachable")
        }

        @MainActor
        private func runOnMain(
            config: KSConfig,
            configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
        ) async throws(KSError) -> Int32 {
            let window = try KSBootOrchestrator.selectWindow(from: config)

            await commandRegistry.setAllowlist(config.security.commandAllowlist)
            await commandRegistry.setRateLimit(config.security.commandRateLimit)

            let host = try KSLinuxDemoHost(windowConfig: window, registry: commandRegistry)
            let mainHandle = _windows.registerMainWindow(
                label: window.label,
                host: host.mainWebView)

            // Phase 1: 윈도우 상태 영속화 — `persistState=true`일 때만 활성화.
            // 메인 루프(=activate) 진입 전에 복원 상태를 호스트에 주입하고,
            // close-request 시점에 디스크에 저장하는 sink를 등록한다.
            let stateStore: KSWindowStateStore? =
                window.persistState
                ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
                : nil
            if let restored = stateStore?.load(label: window.label) {
                host.applyRestoredState(restored)
            }
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
                try host.setResponseCSP(config.security.csp)
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
            try host.start(url: url, devtools: effectiveDevtools)

            // RFC-008 §2.4: 보안 설정 적용 — Win/Mac 패턴과 통일.
            if config.security.contextMenu == .disabled {
                host.setDefaultContextMenusEnabled(false)
            }
            if !config.security.allowExternalDrop {
                host.setAllowExternalDrop(false)
                try? host.installFileDropEmitter()
            }
            let shellRef = _shell
            try host.installSecurityHandlers(
                allowPopups: config.security.allowPopups,
                openExternal: { urlStr in
                    guard let u = URL(string: urlStr) else { return }
                    Task.detached { try? await shellRef.openExternal(u) }
                })

            // RFC-008 #2.5: appMenu / windowMenu 설치 — Win/Mac 패턴과 통일.
            if let appMenu = config.menu?.appMenu {
                try await _menus.installAppMenu(appMenu)
            }
            if let windowMenu = config.menu?.windowMenu {
                try await _menus.installWindowMenu(mainHandle, items: windowMenu)
            }

            if let trayConfig = config.tray {
                try? await _tray.install(trayConfig)
            }

            // RFC-008 #2.6: 메뉴/트레이 클릭을 JS `menu` 이벤트와
            // commandRegistry.dispatch로 라우팅. Win/Mac 패턴과 통일.
            KSLinuxCommandRouter.shared.clear()
            KSLinuxCommandRouter.shared.subscribe { [weak host] command, itemID in
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
                KSLinuxAutostartBackend(identifier: config.app.identifier)
            }
            let deepLinkPair: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = {
                guard let dlc = config.deepLink else { return nil }
                let backend = KSLinuxDeepLinkBackend(identifier: config.app.identifier)
                if dlc.autoRegisterOnLaunch {
                    for s in dlc.schemes {
                        try? backend.register(scheme: s)
                    }
                }
                return (backend, dlc)
            }()
            _autostart = autostartBackend
            _deepLink = deepLinkPair?.backend

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

            let exitCode = host.runMessageLoop()
            KSWindowEmitHub.shared.unregister(label: window.label)
            return exitCode
        }
    }

    extension KSLinuxPlatform {
        // 부팅 헬퍼는 `KSBootOrchestrator` (KalsaeCore)로 통합됨.
    }

    // MARK: - Phase 3 데모 호스트

    /// Phase 3 데모 실행 파일에서 사용하는 단일 윈도우 호스트.
    /// `KSWindowsDemoHost` / `KSMacDemoHost`와 동일하게 설계되어
    /// `KalsaeDemo`이 명령 등록 로직을 공유할 수 있다.
    @MainActor
    public final class KSLinuxDemoHost: KSDemoHost {
        public let registry: KSCommandRegistry
        nonisolated private let webview: GtkWebViewHost
        public let bridge: GtkBridge
        private let windowConfig: KSWindowConfig

        /// 대기 중인 초기 탐색 + devtools 플래그.
        /// GtkApplication이 "activate"를 발행하고 실제 웹뷰가 살아있어
        /// 진 후에 적용된다.
        private var pendingURL: String?
        private var pendingDevtools = false

        public init(
            windowConfig: KSWindowConfig,
            registry: KSCommandRegistry
        ) throws(KSError) {
            self.registry = registry
            self.windowConfig = windowConfig
            // `KSWindowConfig.transparent`는 Windows 전용 (v0.3 시점). Linux
            // 백엔드는 1회 경고 로그를 남기고 무시한다.
            if windowConfig.transparent {
                Self.warnTransparentOnce()
            }
            let appId = "app.Kalsae.\(windowConfig.label)"
            self.webview = GtkWebViewHost(
                appId: appId,
                title: windowConfig.title,
                width: windowConfig.width,
                height: windowConfig.height)
            self.bridge = GtkBridge(host: webview, registry: registry, windowLabel: windowConfig.label)
        }

        /// 초기 탐색을 대기열에 등록한다. GtkApplication은 메인 루프가 실행되고
        /// "activate"를 발행할 때만 윈도우를 생성하므로
        /// 모든 것을 적용하는 활성화 콜백을 등록한다.
        public func start(url: String, devtools: Bool) throws(KSError) {
            try bridge.install()
            self.pendingURL = url
            self.pendingDevtools = devtools
            // 최소 사용 C 활성화 훅을 초기 내비게이션에 재사용한다.
            let box = ActivationBox(owner: self)
            let ctx = Unmanaged.passRetained(box).toOpaque()
            ks_gtk_host_set_on_activate(
                webview.hostPtr,
                linuxActivationTrampoline,
                ctx)
        }

        /// 활성화 전에 적용할 윈도우 복원 상태를 등록한다. `start` 호출
        /// 이전이거나 적어도 메인 루프 진입 전에 호출되어야 한다.
        public func applyRestoredState(_ state: KSPersistedWindowState) {
            webview.applyRestoredState(state)
        }

        /// 윈도우 상태 저장 sink를 등록한다. close-request 시점에
        /// 메인 스레드에서 동기적으로 호출된다.
        public func setWindowStateSaveSink(
            _ sink: (@MainActor (KSPersistedWindowState) -> Void)?
        ) {
            webview.setWindowStateSaveSink(sink)
        }

        /// `root`에서 에셋을 제공하도록 `ks://` 스킴 핸들러를 바인딩한다.
        public func setAssetRoot(_ root: URL) throws(KSError) {
            try webview.setAssetRoot(root)
        }

        // RFC-008 §2.4 — 보안 핸들러 프록시.
        public func setDefaultContextMenusEnabled(_ enabled: Bool) {
            webview.setDefaultContextMenusEnabled(enabled)
        }
        public func setAllowExternalDrop(_ allow: Bool) {
            webview.setAllowExternalDrop(allow)
        }
        public func installFileDropEmitter() throws(KSError) {
            try webview.installFileDropEmitter()
        }
        public func installSecurityHandlers(
            allowPopups: Bool,
            openExternal: (@MainActor (String) -> Void)?
        ) throws(KSError) {
            try webview.installSecurityHandlers(
                allowPopups: allowPopups, openExternal: openExternal)
        }

        /// 모든 `ks://` 에셋 응답에 대한 Content-Security-Policy 헤더를 설정한다.
        /// `addDocumentCreatedScript`에서 설치하는 메타 태그 폴백을 보완한다.
        public func setResponseCSP(_ csp: String) throws(KSError) {
            try webview.setResponseCSP(csp)
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

        fileprivate var mainWebView: GtkWebViewHost { webview }

        fileprivate func applyPendingNavigation() {
            if pendingDevtools { try? webview.openDevToolsNow() }
            if let url = pendingURL {
                try? webview.navigate(url: url)
            }
            pendingURL = nil
        }

        public func runMessageLoop() -> Int32 {
            webview.run()
        }

        public func emit(_ event: String, payload: any Encodable) throws(KSError) {
            try bridge.emit(event: event, payload: payload)
        }

        /// 현재 문서를 다시 로드한다. dev 라이브 리로드(`KALSAE_DEV_RELOAD=1`)
        /// 에서 사용된다.
        public func reload() {
            webview.reload()
        }

        nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
            webview.postJob(block)
        }

        /// 데모 앱의 정상 종료를 요청한다.
        nonisolated public func requestQuit() {
            webview.quit()
        }

        // MARK: - Phase 3 라이프사이클 훅

        fileprivate var onBeforeCloseSwift: (@MainActor () -> Bool)?
        fileprivate var onSuspendSwift: (@MainActor () -> Void)?
        fileprivate var onResumeSwift: (@MainActor () -> Void)?
        /// C 클로즈 핸들러 트램폴린의 미소유 포인터가 유효하도록 유지함.
        private var closeHandlerBox: CloseHandlerBox?
        /// D-Bus 전원 트램폴린의 미소유 포인터가 유효하도록 유지함.
        private var powerBox: PowerBox?

        public func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?) {
            onBeforeCloseSwift = cb
            if cb != nil {
                if closeHandlerBox == nil {
                    let box = CloseHandlerBox(host: self)
                    closeHandlerBox = box
                    let ctx = Unmanaged.passUnretained(box).toOpaque()
                    ks_gtk_host_set_close_handler(
                        webview.hostPtr,
                        linuxCloseHandlerTrampoline,
                        ctx)
                }
            } else {
                ks_gtk_host_set_close_handler(webview.hostPtr, nil, nil)
                closeHandlerBox = nil
            }
        }

        public func setOnSuspend(_ cb: (@MainActor () -> Void)?) {
            onSuspendSwift = cb
            ensurePowerBox()
            if cb != nil, let pb = powerBox {
                let ctx = Unmanaged.passUnretained(pb).toOpaque()
                ks_gtk_host_set_on_suspend(
                    webview.hostPtr,
                    linuxSuspendTrampoline, ctx)
            } else {
                ks_gtk_host_set_on_suspend(webview.hostPtr, nil, nil)
            }
        }

        public func setOnResume(_ cb: (@MainActor () -> Void)?) {
            onResumeSwift = cb
            ensurePowerBox()
            if cb != nil, let pb = powerBox {
                let ctx = Unmanaged.passUnretained(pb).toOpaque()
                ks_gtk_host_set_on_resume(
                    webview.hostPtr,
                    linuxResumeTrampoline, ctx)
            } else {
                ks_gtk_host_set_on_resume(webview.hostPtr, nil, nil)
            }
        }

        private func ensurePowerBox() {
            if powerBox == nil { powerBox = PowerBox(host: self) }
        }

        /// JS `__ks.*` 내장 명령을 레지스트리에 등록한다.
        ///
        /// `KSApp.boot()` 내부에서 자동으로 호출된다.
        @MainActor
        public func registerBuiltinCommands(
            platformName: String = "Linux (GTK4 + WebKitGTK 6.0)",
            shellScope: KSShellScope = .init(),
            notificationScope: KSNotificationScope = .init(),
            fsScope: KSFSScope = .init(),
            httpScope: KSHTTPScope = .init(),
            navigationScope: KSNavigationScope = .init(),
            autostart: (any KSAutostartBackend)? = nil,
            deepLink: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = nil,
            appDirectory: URL? = nil,
            // RFC-008 #2.14: 플랫폼이 공유 백엔드 인스턴스를 주입할 수
            // 있도록 한다. nil이면 기존 동작 유지(새 인스턴스 생성).
            windows: (any KSWindowBackend)? = nil,
            shell: (any KSShellBackend)? = nil,
            clipboard: (any KSClipboardBackend)? = nil,
            notifications: (any KSNotificationBackend)? = nil,
            dialogs: (any KSDialogBackend)? = nil
        ) async {
            // 공유 백엔드가 주입되면 그것을, 아니면 새 인스턴스를 사용해
            // 메인 윈도우 핸들을 등록한다(이전 동작과 동일하지만 공유 시
            // 동일 레지스트리에 등록되어 일관성이 확보된다).
            let linuxWindows = (windows as? KSLinuxWindowBackend) ?? KSLinuxWindowBackend()
            let handle = linuxWindows.registerMainWindow(
                label: windowConfig.label, host: webview)
            let mainProvider: @Sendable () -> KSWindowHandle? = { handle }
            let quitBlock: @Sendable () -> Void = { [weak self] in self?.requestQuit() }
            await KSBuiltinCommands.register(
                into: registry,
                windows: linuxWindows,
                shell: shell ?? KSLinuxShellBackend(),
                clipboard: clipboard ?? KSLinuxClipboardBackend(),
                notifications: notifications ?? KSLinuxNotificationBackend(),
                dialogs: dialogs ?? KSLinuxDialogBackend(),
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

        // MARK: - 미구현 옵션 1회 경고

        nonisolated(unsafe) private static var didWarnTransparent = false
        nonisolated(unsafe) private static let warnLock = NSLock()

        fileprivate static func warnTransparentOnce() {
            warnLock.lock()
            defer { warnLock.unlock() }
            guard !didWarnTransparent else { return }
            didWarnTransparent = true
            FileHandle.standardError.write(
                Data(
                    "[Kalsae][Linux] KSWindowConfig.transparent=true 는 Linux에서 아직 지원되지 않습니다 (Windows 전용, v0.3). 무시됩니다.\n"
                        .utf8))
        }
    }

    /// 활성화 C 콜백을 통해 전달되는 힙 할당 홀더.
    private final class ActivationBox: @unchecked Sendable {
        weak var owner: KSLinuxDemoHost?
        init(owner: KSLinuxDemoHost) { self.owner = owner }
    }

    /// 클로즈 요청 C 트램폴린용 힙 할당 홀더.
    private final class CloseHandlerBox: @unchecked Sendable {
        weak var host: KSLinuxDemoHost?
        init(host: KSLinuxDemoHost) { self.host = host }
    }

    /// D-Bus 전원 트램폴린용 힙 할당 홀더.
    private final class PowerBox: @unchecked Sendable {
        weak var host: KSLinuxDemoHost?
        init(host: KSLinuxDemoHost) { self.host = host }
    }

    internal import CKalsaeGtk

    private let linuxActivationTrampoline:
        @convention(c) (
            UnsafeMutableRawPointer?
        ) -> Void = { raw in
            guard let raw else { return }
            let box = Unmanaged<ActivationBox>.fromOpaque(raw).takeRetainedValue()
            MainActor.assumeIsolated {
                box.owner?.applyPendingNavigation()
            }
        }

    /// 클로즈 요청 콜백의 C 트램폴린. 닫기를 수행하지 않으려면 1을,
    /// 허용하려면 0을 반환한다. GTK 메인 스레드에서 동기적으로 호출된다.
    private let linuxCloseHandlerTrampoline:
        @convention(c) (
            UnsafeMutableRawPointer?
        ) -> Int32 = { raw in
            guard let raw else { return 0 }
            let box = Unmanaged<CloseHandlerBox>.fromOpaque(raw).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard let cb = box.host?.onBeforeCloseSwift else { return 0 }
                return cb() ? 1 : 0
            }
        }

    /// D-Bus PrepareForSleep → suspend에 대한 C 트램폴린.
    private let linuxSuspendTrampoline:
        @convention(c) (
            UnsafeMutableRawPointer?
        ) -> Void = { raw in
            guard let raw else { return }
            let box = Unmanaged<PowerBox>.fromOpaque(raw).takeUnretainedValue()
            MainActor.assumeIsolated {
                box.host?.onSuspendSwift?()
            }
        }

    /// D-Bus PrepareForSleep(false) → resume에 대한 C 트램폴린.
    private let linuxResumeTrampoline:
        @convention(c) (
            UnsafeMutableRawPointer?
        ) -> Void = { raw in
            guard let raw else { return }
            let box = Unmanaged<PowerBox>.fromOpaque(raw).takeUnretainedValue()
            MainActor.assumeIsolated {
                box.host?.onResumeSwift?()
            }
        }

#endif
