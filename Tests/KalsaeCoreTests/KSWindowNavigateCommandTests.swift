import Foundation

import Testing

@testable import KalsaeCore

@Suite("Window navigate IPC")
@MainActor
struct KSWindowNavigateCommandTests {
    private func makeRegistry(
        allow: [String]
    ) async -> (KSCommandRegistry, RecordingWindowBackend, KSWindowHandle, KSWindowHandle) {
        let main = KSWindowHandle(label: "main", rawValue: 1)
        let secondary = KSWindowHandle(label: "chat", rawValue: 2)
        let backend = RecordingWindowBackend()
        await backend.seed(main, webView: RecordingWebView())
        await backend.seed(secondary, webView: RecordingWebView())
        let registry = KSCommandRegistry()
        let resolver = WindowResolver(windows: backend, mainWindow: { main })
        let appDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fsCtx = KSFSScope.ExpansionContext.current(appDirectory: appDir)
        await KSBuiltinCommands.registerWindowCommands(
            into: registry,
            windows: backend,
            resolver: resolver,
            fsScope: KSFSScope(),
            fsCtx: fsCtx,
            navigationScope: KSNavigationScope(allow: allow))
        return (registry, backend, main, secondary)
    }

    private func dispatch(
        _ registry: KSCommandRegistry,
        _ name: String,
        args: String
    ) async -> Result<Data, KSError> {
        await registry.dispatch(name: name, args: Data(args.utf8))
    }

    @Test("navigate routes to explicit window and loads URL")
    func navigateExplicitWindow() async throws {
        let url = "https://chatbot.intra.example.com/app"
        let (registry, backend, _, secondary) = await makeRegistry(
            allow: ["https://chatbot.intra.example.com/**"])

        let result = await dispatch(
            registry,
            "__ks.window.navigate",
            args: #"{"url":"https://chatbot.intra.example.com/app","window":"chat"}"#)
        switch result {
        case .success:
            break
        case .failure(let error):
            Issue.record("expected success, got \(error)")
        }

        let loaded = await backend.lastLoadedURL(label: secondary.label)
        #expect(loaded?.absoluteString == url)
    }

    @Test("navigate falls back to main window when label is omitted")
    func navigateFallsBackToMainWindow() async throws {
        let url = "https://chatbot.intra.example.com/home"
        let (registry, backend, main, _) = await makeRegistry(
            allow: ["https://chatbot.intra.example.com/**"])

        let result = await dispatch(
            registry,
            "__ks.window.navigate",
            args: #"{"url":"https://chatbot.intra.example.com/home"}"#)
        switch result {
        case .success:
            break
        case .failure(let error):
            Issue.record("expected success, got \(error)")
        }

        let loaded = await backend.lastLoadedURL(label: main.label)
        #expect(loaded?.absoluteString == url)
    }

    @Test("navigate rejects URL outside navigation allowlist")
    func navigateRejectsDisallowedURL() async {
        let (registry, backend, main, _) = await makeRegistry(
            allow: ["https://allowed.example.com/**"])

        let result = await dispatch(
            registry,
            "__ks.window.navigate",
            args: #"{"url":"https://chatbot.intra.example.com/app"}"#)
        switch result {
        case .success:
            Issue.record("expected failure but got success")
        case .failure(let error):
            #expect(error.code == .commandNotAllowed)
        }

        let loaded = await backend.lastLoadedURL(label: main.label)
        #expect(loaded == nil)
    }

    @Test("navigate rejects malformed URLs before loading")
    func navigateRejectsMalformedURL() async {
        let (registry, backend, main, _) = await makeRegistry(allow: [])

        let result = await dispatch(
            registry,
            "__ks.window.navigate",
            args: #"{"url":"http://"}"#)
        switch result {
        case .success:
            Issue.record("expected failure but got success")
        case .failure(let error):
            #expect(error.code == .invalidArgument)
        }

        let loaded = await backend.lastLoadedURL(label: main.label)
        #expect(loaded == nil)
    }
}
private actor RecordingWindowBackend: KSWindowBackend {
    private var handles: [KSWindowHandle] = []
    private var webViews: [String: RecordingWebView] = [:]

    func seed(_ handle: KSWindowHandle, webView: RecordingWebView) {
        handles.append(handle)
        webViews[handle.label] = webView
    }

    func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
        throw KSError(code: .unsupportedPlatform, message: "stub")
    }

    func close(_ handle: KSWindowHandle) async throws(KSError) {}
    func show(_ handle: KSWindowHandle) async throws(KSError) {}
    func hide(_ handle: KSWindowHandle) async throws(KSError) {}
    func focus(_ handle: KSWindowHandle) async throws(KSError) {}

    func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend {
        guard let webView = webViews[handle.label] else {
            throw KSError(code: .invalidArgument, message: "missing webview")
        }
        return webView
    }

    func all() async -> [KSWindowHandle] { handles }

    func find(label: String) async -> KSWindowHandle? {
        handles.first { $0.label == label }
    }

    func lastLoadedURL(label: String) async -> URL? {
        await webViews[label]?.lastLoadedURL
    }

    func reload(_ handle: KSWindowHandle) async throws(KSError) {}
    func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {}
    func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {}
}
private actor RecordingWebView: KSWebViewBackend {
    private(set) var lastLoadedURL: URL?

    func load(url: URL) async throws(KSError) {
        lastLoadedURL = url
    }

    func evaluateJavaScript(_ source: String) async throws(KSError) -> Data? { nil }
    func postMessage(_ message: KSIPCMessage) async throws(KSError) {}
    func setMessageHandler(
        _ handler: @Sendable @escaping (KSIPCMessage) async -> Void
    ) async {}
    func setContentSecurityPolicy(_ csp: String) async throws(KSError) {}
    func openDevTools() async throws(KSError) {}
}
