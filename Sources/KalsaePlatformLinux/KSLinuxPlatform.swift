#if os(Linux)
public import KalsaeCore
public import Foundation

/// Linux platform backend (GTK4 + WebKitGTK 6.0). Phase 3 implementation:
/// boots enough surface area to prove Phase 1's IPC contract against
/// `WebKitWebView`. Full PAL coverage (dialogs, tray, menus,
/// notifications) lands in later phases.
public final class KSLinuxPlatform: KSPlatform, @unchecked Sendable {
    public var name: String { "Linux (GTK4 + WebKitGTK 6.0)" }

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
            message: "KSLinuxPlatform.run() lands with the full PAL. Use KSLinuxDemoHost for Phase 3 smoke tests.")
    }
}

// MARK: - Phase 3 demo host

/// Single-window host used by the Phase 3 demo executable. Shaped
/// identically to `KSWindowsDemoHost` / `KSMacDemoHost` so that
/// `KalsaeDemo` can share its command-registration logic.
@MainActor
public final class KSLinuxDemoHost {
    public let registry: KSCommandRegistry
    nonisolated private let webview: GtkWebViewHost
    public let bridge: GtkBridge

    /// Pending initial navigation + devtools flag, applied once
    /// GtkApplication emits "activate" and the underlying WebView is
    /// actually alive.
    private var pendingURL: String?
    private var pendingDevtools = false

    public init(windowConfig: KSWindowConfig,
                registry: KSCommandRegistry) throws(KSError) {
        self.registry = registry
        let appId = "app.Kalsae.\(windowConfig.label)"
        self.webview = GtkWebViewHost(
            appId: appId,
            title: windowConfig.title,
            width: windowConfig.width,
            height: windowConfig.height)
        self.bridge = GtkBridge(host: webview, registry: registry)
    }

    /// Queues the initial navigation. GtkApplication only creates the
    /// window when its main loop starts running and emits "activate",
    /// so we register an activation callback that applies everything.
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

    /// Binds the `ks://` scheme handler to serve assets from `root`.
    public func setAssetRoot(_ root: URL) throws(KSError) {
        try webview.setAssetRoot(root)
    }

    /// Sets the Content-Security-Policy header for every `ks://` asset
    /// response. Complements the meta-tag fallback installed by
    /// `addDocumentCreatedScript`.
    public func setResponseCSP(_ csp: String) throws(KSError) {
        try webview.setResponseCSP(csp)
    }

    /// Queues a JS snippet to run at the start of every document.
    public func addDocumentCreatedScript(_ script: String) throws(KSError) {
        try webview.addDocumentCreatedScript(script)
    }

    fileprivate func applyPendingNavigation() {
        if pendingDevtools { try? webview.openDevTools() }
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

    nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
        webview.postJob(block)
    }

    /// Requests an orderly shutdown of the demo app.
    nonisolated public func requestQuit() {
        webview.quit()
    }

    // MARK: - Phase C4 lifecycle hooks (no-op stubs on Linux preview)
    public func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?) { _ = cb }
    public func setOnSuspend(_ cb: (@MainActor () -> Void)?) { _ = cb }
    public func setOnResume(_ cb: (@MainActor () -> Void)?) { _ = cb }
}

/// Heap-allocated holder passed through the activation C callback.
private final class ActivationBox: @unchecked Sendable {
    weak var owner: KSLinuxDemoHost?
    init(owner: KSLinuxDemoHost) { self.owner = owner }
}

internal import CKalsaeGtk

private let linuxActivationTrampoline: @convention(c) (
    UnsafeMutableRawPointer?
) -> Void = { raw in
    guard let raw else { return }
    let box = Unmanaged<ActivationBox>.fromOpaque(raw).takeRetainedValue()
    MainActor.assumeIsolated {
        box.owner?.applyPendingNavigation()
    }
}

// MARK: - Not-implemented PAL backends (Phase 3 stubs)

private struct NotImplementedBackend:
    KSWindowBackend, KSDialogBackend, KSMenuBackend, KSNotificationBackend
{
    private func fail<T>() throws(KSError) -> T {
        throw KSError(code: .unsupportedPlatform,
                      message: "Not implemented in Phase 3.")
    }
    private func failVoid() throws(KSError) {
        throw KSError(code: .unsupportedPlatform,
                      message: "Not implemented in Phase 3.")
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
