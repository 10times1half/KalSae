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
            let window = try Self.selectWindow(from: config)

            await commandRegistry.setAllowlist(config.security.commandAllowlist)
            await commandRegistry.setRateLimit(config.security.commandRateLimit)

            let host = try KSiOSDemoHost(windowConfig: window, registry: commandRegistry)

            let resourceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(config.build.frontendDist)
            let servingMode = Self.decideServingMode(
                windowURL: window.url,
                devServerURL: config.build.devServerURL,
                resourceRoot: resourceRoot)

            if case .virtualHost(let servedRoot) = servingMode {
                try host.setAssetRoot(servedRoot)
            }

            host.setCrossOriginIsolation(config.security.crossOriginIsolation)

            try host.addDocumentCreatedScript(Self.cspInjectionScript(config.security.csp))

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
                autostart: nil,  // autostart is not applicable on iOS
                deepLink: deepLinkPair,
                appDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

            try await configure(self)

            #if DEBUG
                let effectiveDevtools = config.security.devtools
            #else
                let effectiveDevtools = false
            #endif
            try host.start(
                url: Self.resolveStartURL(
                    windowURL: window.url,
                    devServerURL: config.build.devServerURL,
                    servingMode: servingMode),
                devtools: effectiveDevtools)

            return host.runMessageLoop()
        }
    }

    // MARK: - Private helpers

    extension KSiOSPlatform {
        fileprivate enum ServingMode {
            case virtualHost(URL)
            case devServer
            case fallback
        }

        fileprivate static func selectWindow(from config: KSConfig) throws(KSError) -> KSWindowConfig {
            guard let first = config.windows.first else {
                throw KSError.configInvalid("config.windows is empty")
            }
            return first
        }

        fileprivate static func decideServingMode(
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

        fileprivate static func resolveStartURL(
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

        fileprivate static func isDirectory(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && isDir.boolValue
        }

        fileprivate static func isRemoteURL(_ s: String) -> Bool {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            if trimmed.lowercased() == "about:blank" { return false }
            let lower = trimmed.lowercased()
            return lower.hasPrefix("http://") || lower.hasPrefix("https://")
        }

        fileprivate static func cspInjectionScript(_ csp: String) -> String {
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
#endif
