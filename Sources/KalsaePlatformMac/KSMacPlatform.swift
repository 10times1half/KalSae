#if os(macOS)
internal import AppKit
public import KalsaeCore
public import Foundation

/// macOS platform backend (AppKit + WKWebView). Phase 2 implementation:
/// boots enough surface area to prove Phase 1's IPC contract against
/// `WKWebView`. Full PAL coverage (dialogs, tray, menus, notifications)
/// is scheduled for later phases.
public final class KSMacPlatform: KSPlatform, @unchecked Sendable {
    public var name: String { "macOS (AppKit + WKWebView)" }

    public let commandRegistry = KSCommandRegistry()

    public var windows: any KSWindowBackend { NotImplementedBackend() }
    public var dialogs: any KSDialogBackend { NotImplementedBackend() }
    public var tray: (any KSTrayBackend)? { nil }
    public var menus: any KSMenuBackend { NotImplementedBackend() }
    public var notifications: any KSNotificationBackend { NotImplementedBackend() }

    public init() {}

    public func run(
        config: KSConfig,
        configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
    ) async throws(KSError) -> Never {
        throw KSError(
            code: .unsupportedPlatform,
            message: "KSMacPlatform.run() lands together with the full PAL. Use KSMacDemoHost for Phase 2 smoke tests.")
    }
}

// MARK: - Phase 2 demo host

/// Single-window host used by the Phase 2 demo executable. Shaped
/// identically to `KSWindowsDemoHost` so that the `KalsaeDemo` target
/// can share its command-registration logic.
@MainActor
public final class KSMacDemoHost {
    public let registry: KSCommandRegistry
    nonisolated private let window: KSMacWindow
    private let webview: WKWebViewHost
    public let bridge: WKBridge

    public init(windowConfig: KSWindowConfig,
                registry: KSCommandRegistry) throws(KSError) {
        KSMacApp.shared.ensureInitialized()

        self.registry = registry
        self.window = try KSMacWindow(config: windowConfig)
        self.webview = WKWebViewHost(label: windowConfig.label)
        self.bridge = WKBridge(host: webview, registry: registry)
    }

    public func start(url: String, devtools: Bool) throws(KSError) {
        window.setContentView(webview.webView)
        try bridge.install()
        try webview.navigate(url: url)
        if devtools {
            try? webview.openDevTools()
        }
    }

    /// Binds the `ks://` scheme handler to serve assets from `root`.
    /// On macOS the navigation URL is `ks://app/index.html`.
    public func setAssetRoot(_ root: URL) throws(KSError) {
        try webview.setAssetRoot(root)
    }

    /// Queues a JS snippet to run at the start of every document.
    public func addDocumentCreatedScript(_ script: String) throws(KSError) {
        try webview.addDocumentCreatedScript(script)
    }

    public func runMessageLoop() -> Int32 {
        KSMacApp.shared.runMessageLoop()
    }

    public func emit(_ event: String, payload: any Encodable) throws(KSError) {
        try bridge.emit(event: event, payload: payload)
    }

    /// Posts a closure onto the UI thread. API-compatible with
    /// `KSWindowsDemoHost.postJob`.
    nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
        window.postJob(block)
    }

    /// Requests an orderly shutdown of the demo app.
    nonisolated public func requestQuit() {
        window.postJob {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - Not-implemented PAL backends (Phase 2 stubs)

private struct NotImplementedBackend:
    KSWindowBackend, KSDialogBackend, KSMenuBackend, KSNotificationBackend
{
    private func fail<T>() throws(KSError) -> T {
        throw KSError(code: .unsupportedPlatform,
                      message: "Not implemented in Phase 2.")
    }
    private func failVoid() throws(KSError) {
        throw KSError(code: .unsupportedPlatform,
                      message: "Not implemented in Phase 2.")
    }

    func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle { try fail() }
    func close(_ handle: KSWindowHandle) async throws(KSError) { try failVoid() }
    func show(_ handle: KSWindowHandle) async throws(KSError) { try failVoid() }
    func hide(_ handle: KSWindowHandle) async throws(KSError) { try failVoid() }
    func focus(_ handle: KSWindowHandle) async throws(KSError) { try failVoid() }
    func setTitle(_ h: KSWindowHandle, title: String) async throws(KSError) { try failVoid() }
    func setSize(_ h: KSWindowHandle, width: Int, height: Int) async throws(KSError) { try failVoid() }
    func webView(for h: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend { try fail() }
    func all() async -> [KSWindowHandle] { [] }
    func find(label: String) async -> KSWindowHandle? { nil }

    func openFile(options: KSOpenFileOptions, parent: KSWindowHandle?) async throws(KSError) -> [URL] { try fail() }
    func saveFile(options: KSSaveFileOptions, parent: KSWindowHandle?) async throws(KSError) -> URL? { try fail() }
    func selectFolder(options: KSSelectFolderOptions, parent: KSWindowHandle?) async throws(KSError) -> URL? { try fail() }
    func message(_ options: KSMessageOptions, parent: KSWindowHandle?) async throws(KSError) -> KSMessageResult { try fail() }

    func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) { try failVoid() }
    func installWindowMenu(_ h: KSWindowHandle, items: [KSMenuItem]) async throws(KSError) { try failVoid() }
    func showContextMenu(_ items: [KSMenuItem], at point: KSPoint, in h: KSWindowHandle?) async throws(KSError) { try failVoid() }

    func requestPermission() async -> Bool { false }
    func post(_ notification: KSNotification) async throws(KSError) { try failVoid() }
    func cancel(id: String) async {}
}
#endif
