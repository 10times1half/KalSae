#if os(Windows)
    internal import WinSDK
    internal import Logging
    public import KalsaeCore
    internal import Foundation

    /// Windows 플랫폼 백엔드 (Win32 HWND + WebView2 COM).
    ///
    /// 전체 PAL 커버리지 완성: 윈도우, 다이얼로그, 트레이, 메뉴, 알림,
    /// 클립보드, 셸, 액셀러레이터, 자동시작, 딥링크, 단일 인스턴스,
    /// 윈도우 상태 영속화. 모든 PAL 서비스가 Win32에 완전히 연결되어 있다.
    // @unchecked: Win32 thread confinement (HWND affinity) — actor cannot model OS thread binding
    public final class KSWindowsPlatform: KSPlatform, @unchecked Sendable {
        public var name: String { "Windows (Win32 + WebView2)" }

        public let commandRegistry: KSCommandRegistry

        /// Windows PAL 백엔드. 모든 PAL 서비스가 Win32에 완전히 연결되어 있다.
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

        private let _windows: KSWindowsWindowBackend
        private let _dialogs: KSWindowsDialogBackend
        private let _menus: KSWindowsMenuBackend
        private let _tray: KSWindowsTrayBackend
        private let _notifications: KSWindowsNotificationBackend
        private let _shell: KSWindowsShellBackend
        private let _clipboard: KSWindowsClipboardBackend
        private let _accelerators: KSWindowsAcceleratorBackend
        // run(config:configure:) 중에 설정됨. @unchecked Sendable 계약으로 보호.
        private nonisolated(unsafe) var _autostart: (any KSAutostartBackend)?
        private nonisolated(unsafe) var _deepLink: (any KSDeepLinkBackend)?

        public init() {
            let registry = KSCommandRegistry()
            self.commandRegistry = registry
            self._windows = KSWindowsWindowBackend(registry: registry)
            self._dialogs = KSWindowsDialogBackend()
            self._menus = KSWindowsMenuBackend()
            self._tray = KSWindowsTrayBackend()
            self._notifications = KSWindowsNotificationBackend()
            self._shell = KSWindowsShellBackend()
            self._clipboard = KSWindowsClipboardBackend()
            self._accelerators = KSWindowsAcceleratorBackend()
        }

        public func run(
            config: KSConfig,
            configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
        ) async throws(KSError) -> Never {
            let code = try await runOnMain(config: config, configure: configure)
            ExitProcess(UINT(UInt32(bitPattern: code)))
        }

        @MainActor
        private func runOnMain(
            config: KSConfig,
            configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
        ) async throws(KSError) -> Int32 {
            let window = try Self.selectWindow(from: config)

            await commandRegistry.setAllowlist(config.security.commandAllowlist)
            await commandRegistry.setRateLimit(config.security.commandRateLimit)

            let stateStore: KSWindowStateStore? =
                window.persistState
                ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
                : nil
            let restoredState = stateStore?.load(label: window.label)

            let host = try KSWindowsDemoHost(
                windowConfig: window,
                registry: commandRegistry,
                restoredState: restoredState)

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

            // 보안: 릴리스 빌드에서는 설정값에 무관하게 개발자 도구가 강제 비활성화된다.
            // AGENTS §5 + 감사 결과 #8 참조.
            #if DEBUG
                let effectiveDevtools = config.security.devtools
            #else
                let effectiveDevtools = false
            #endif

            if case .virtualHost(let servedRoot) = servingMode {
                try host.prepare(devtools: effectiveDevtools)
                let resolver = KSAssetResolver(root: servedRoot, cache: KSAssetCache())
                try host.setResourceHandler(
                    resolver: resolver,
                    csp: config.security.csp,
                    host: Self.virtualHost)
            }

            try host.addDocumentCreatedScript(Self.cspInjectionScript(config.security.csp))

            if config.security.contextMenu == .disabled {
                host.setDefaultContextMenusEnabled(false)
            }
            if !config.security.allowExternalDrop {
                host.setAllowExternalDrop(false)
                try? host.installFileDropEmitter()
            }

            let url = Self.resolveStartURL(
                windowURL: window.url,
                devServerURL: config.build.devServerURL,
                servingMode: servingMode)
            try host.startPrepared(url: url, devtools: effectiveDevtools)

            _notifications.setAppUserModelID(
                config.notifications?.appUserModelID ?? config.app.identifier)
            _notifications.attachTray(_tray)

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

            KSWindowsCommandRouter.shared.clear()
            KSWindowsCommandRouter.shared.subscribe { [weak host] command, itemID in
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

            let autostartBackend: (any KSAutostartBackend)? = config.autostart.map {
                KSWindowsAutostartBackend(identifier: config.app.identifier, args: $0.args)
            }
            let deepLinkPair: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = {
                guard let dlc = config.deepLink else { return nil }
                let backend = KSWindowsDeepLinkBackend(identifier: config.app.identifier)
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

    extension KSWindowsPlatform {
        private enum ServingMode: Sendable {
            case virtualHost(URL)
            case devServer
            case fallback
        }

        private static let virtualHost = "app.kalsae"

        private static func selectWindow(from config: KSConfig) throws(KSError) -> KSWindowConfig {
            guard let first = config.windows.first else {
                throw KSError.configInvalid("config.windows is empty")
            }
            return first
        }

        private static func decideServingMode(
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

        private static func resolveStartURL(
            windowURL: String?,
            devServerURL: String,
            servingMode: ServingMode
        ) -> String {
            if let windowURL { return windowURL }
            switch servingMode {
            case .virtualHost:
                return "https://\(virtualHost)/index.html"
            case .devServer, .fallback:
                return devServerURL
            }
        }

        private static func isDirectory(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && isDir.boolValue
        }

        private static func isRemoteURL(_ s: String) -> Bool {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            if trimmed.lowercased() == "about:blank" { return false }
            let lower = trimmed.lowercased()
            return lower.hasPrefix("http://") || lower.hasPrefix("https://")
        }

        private static func cspInjectionScript(_ csp: String) -> String {
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
                                var csp = \"\(escaped)\";
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
#endif
