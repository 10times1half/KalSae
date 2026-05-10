#if os(iOS)
    internal import UIKit
    internal import Darwin
    public import KalsaeCore
    public import Foundation

    // @unchecked: UIKit main thread confinement — actor unsuitable for @UIApplicationMain binding
    public final class KSiOSPlatform: KSPlatform, @unchecked Sendable {
        public var name: String { "iOS (UIKit + WKWebView)" }

        public let commandRegistry: KSCommandRegistry

        public var windows: any KSWindowBackend { _windows }
        public var dialogs: any KSDialogBackend { _dialogs }
        public var tray: (any KSTrayBackend)? { nil }
        public var menus: any KSMenuBackend { _menus }
        public var notifications: any KSNotificationBackend { _notifications }
        public var shell: (any KSShellBackend)? { _shell }
        public var clipboard: (any KSClipboardBackend)? { _clipboard }
        public var accelerators: (any KSAcceleratorBackend)? { nil }
        public var autostart: (any KSAutostartBackend)? { _autostart }
        public var deepLink: (any KSDeepLinkBackend)? { _deepLink }

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
            let code = try await runOnMain(config: config, configure: configure)
            Darwin.exit(Int32(code))
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

            let host = try KSiOSDemoHost(windowConfig: window, registry: commandRegistry)

            // RFC-008 #2.9: 윈도우 상태 영속화. iOS는 UIKit이 layout을 관리하므로
            // 캡처/복원의 의미가 제한적이지만 API 일관성을 위해 sink를 등록한다.
            let stateStore: KSWindowStateStore? =
                window.persistState
                ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
                : nil
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

            let deepLinkPair: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = {
                guard let dlc = config.deepLink else { return nil }
                let backend = KSiOSDeepLinkBackend(identifier: config.app.identifier)
                if dlc.autoRegisterOnLaunch {
                    for s in dlc.schemes {
                        do {
                            try backend.register(scheme: s)
                        } catch {
                            KSLog.logger("platform.ios").error(
                                "deepLink auto-register failed for '\(s)': \(error)")
                        }
                    }
                }
                return (backend, dlc)
            }()
            _deepLink =
                deepLinkPair?.backend as? KSiOSDeepLinkBackend
                ?? KSiOSDeepLinkBackend(identifier: config.app.identifier)

            await KSBuiltinCommands.register(
                into: commandRegistry,
                windows: _windows,
                shell: _shell,
                clipboard: _clipboard,
                notifications: _notifications,
                dialogs: _dialogs,
                mainWindow: { [weak host] in host?.mainHandle },
                // iOS has no programmatic quit API.
                quit: {},
                platformName: name,
                shellScope: config.security.shell,
                notificationScope: config.security.notifications,
                fsScope: config.security.fs,
                httpScope: config.security.http,
                navigationScope: config.security.navigation,
                autostart: nil,  // autostart is not applicable on iOS
                deepLink: deepLinkPair,
                appDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

            // RFC-008 #2.7: Win/Mac/Linux와 동일하게 `start()` 이후에
            // `configure(self)`를 호출한다. 이전에는 configure가 먼저 호출되어
            // configure 클로저 안에서 `host.emit()`을 부르면 웹뷰가 아직
            // navigate 되지 않아 메시지가 유실되는 문제가 있었다.
            #if DEBUG
                let effectiveDevtools = config.security.devtools
            #else
                let effectiveDevtools = false
            #endif
            try host.start(
                url: KSBootOrchestrator.resolveStartURL(
                    windowURL: window.url,
                    devServerURL: config.build.devServerURL,
                    servingMode: servingMode,
                    virtualHostURL: "ks://app/index.html"),
                devtools: effectiveDevtools)

            // RFC-008 §4.2: 보안 설정 적용 — Win/Mac/Linux 패턴과 통일.
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

            try await configure(self)

            return host.runMessageLoop()
        }
    }

    // MARK: - Private helpers

    // 부팅 헬퍼는 `KSBootOrchestrator` (KalsaeCore)로 통합됨.
#endif
