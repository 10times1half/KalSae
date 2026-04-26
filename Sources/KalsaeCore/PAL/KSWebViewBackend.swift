public import Foundation

/// Abstracts over WKWebView / WebView2 / WebKitGTK.
public protocol KSWebViewBackend: Sendable {
    /// Loads an absolute URL. In release builds this will usually be a
    /// `ks://localhost/...` URL served by the scheme handler.
    func load(url: URL) async throws(KSError)

    /// Evaluates a JS expression in the main frame. Returned value is JSON
    /// if the expression produced one, or `nil` for `undefined`/`null`.
    @discardableResult
    func evaluateJavaScript(_ source: String) async throws(KSError) -> Data?

    /// Posts a structured message to the JS side. Frontend receives it via
    /// the Kalsae runtime's `listen()` API.
    func postMessage(_ message: KSIPCMessage) async throws(KSError)

    /// Installs a handler invoked for every inbound IPC message from JS.
    /// Exactly one handler may be set per webview.
    func setMessageHandler(
        _ handler: @Sendable @escaping (KSIPCMessage) async -> Void
    ) async

    /// Sets the content-security-policy used by the scheme handler when
    /// serving the root document.
    func setContentSecurityPolicy(_ csp: String) async throws(KSError)

    /// Opens DevTools if the platform and build configuration allow it.
    func openDevTools() async throws(KSError)
}
