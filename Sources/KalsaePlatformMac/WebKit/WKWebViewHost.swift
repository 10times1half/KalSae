#if os(macOS)
internal import AppKit
internal import WebKit
internal import Logging
public import KalsaeCore
public import Foundation

/// Hosts a WKWebView and exposes the small surface that `WKBridge` needs:
/// register an inbound-message handler, navigate to a URL, and send JSON
/// into the page. Mirrors `WebView2Host` on Windows.
@MainActor
public final class WKWebViewHost {
    internal let webView: WKWebView
    private let userContentController: WKUserContentController
    private let log: Logger = KSLog.logger("platform.mac.webview")

    /// Active inbound handler, installed by `WKBridge.install()`.
    private var inbound: ((String) -> Void)?

    /// Lazily created message handler object. Keeping a reference avoids
    /// the `WKUserContentController` weakly dropping it.
    private let messageHandler: KSScriptMessageHandler

    /// Custom scheme resolver kept as a class so `setAssetRoot` can swap
    /// the root without re-creating the web view.
    private let schemeHandler: KSMacSchemeHandler

    public init(label: String) {
        let ucc = WKUserContentController()
        self.userContentController = ucc
        self.messageHandler = KSScriptMessageHandler()
        self.schemeHandler = KSMacSchemeHandler()

        let config = WKWebViewConfiguration()
        config.userContentController = ucc
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "ks")
        if #available(macOS 13.3, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        // 페이지 스크립이 실행되기 전에 런타임을 주입한다.
        let userScript = WKUserScript(
            source: KSRuntimeJS.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false)
        ucc.addUserScript(userScript)

        self.webView = WKWebView(
            frame: .zero,
            configuration: config)
        self.webView.autoresizingMask = [.width, .height]

        // 스크립 메시지 핸들러 연결: JS 쪽은
        // `webkit.messageHandlers.ks.postMessage(obj)`로 전송한다.
        messageHandler.onMessage = { [weak self] text in
            self?.inbound?(text)
        }
        ucc.add(messageHandler, name: "ks")

        log.info("WKWebView created (label=\(label))")
    }

    /// Registers the single inbound-message handler used by `WKBridge`.
    public func onMessage(_ handler: @escaping @MainActor (String) -> Void) throws(KSError) {
        self.inbound = handler
    }

    /// Navigates to `url`. `url` may be a `file://` or `http(s)://` URL.
    public func navigate(url: String) throws(KSError) {
        guard let u = URL(string: url) else {
            throw KSError(code: .webviewInitFailed,
                          message: "Invalid URL: \(url)")
        }
        if u.isFileURL {
            // file URL은 HTML이 참조하는 형제 리소스 로드를 위해
            // 명시적인 읽기 접근 루트가 필요하다.
            webView.loadFileURL(u,
                                allowingReadAccessTo: u.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: u))
        }
    }

    /// Posts a pre-built JSON message into the page. Invokes the JS-side
    /// `window.__KS_receive(...)` hook installed by `KSRuntimeJS`.
    public func postJSON(_ json: String) throws(KSError) {
        // JSON은 이미 유효한 JS 리터럴이므로 식에 그대로 펼쳐 넣는다.
        // 페이로드에 `</script>`가 들어있을 경우를 대비해 이스케이프한다
        // (여기서는 문제가 없지만 Windows 경로와 동일하게 맞춘다).
        let script = "window.__KS_receive(\(json));"
        webView.evaluateJavaScript(script, completionHandler: { _, err in
            if let err {
                // 의도적으로 async 전용: `postJSON`은 브리지에서
                // 불타고 잊는 fire-and-forget이므로 에러를 전파하지 않는다.
                KSLog.logger("platform.mac.webview")
                    .warning("evaluateJavaScript failed: \(err)")
            }
        })
    }

    /// Enables the Web Inspector if available.
    public func openDevTools() throws(KSError) {
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
            log.info("WKWebView isInspectable = true (right-click → Inspect Element)")
        } else {
            log.warning("Web Inspector requires macOS 13.3+; skipping.")
        }
    }

    /// Binds the `ks://` scheme handler to `root`. Returns the base URL
    /// the caller should navigate to (e.g. `ks://app/`).
    public func setAssetRoot(_ root: URL) throws(KSError) {
        schemeHandler.resolver = KSAssetResolver(root: root)
    }

    /// Queues a JS snippet to run at the start of every document.
    public func addDocumentCreatedScript(_ script: String) throws(KSError) {
        let us = WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false)
        userContentController.addUserScript(us)
    }
}

// MARK: - ks:// scheme handler
//
// CSP 응답 헤더와 함께 `KSAssetResolver`의 자산을 제공해 WKWebView가
// 응답별 보안 정책을 존중하도록 한다. 메인 큐에서 실행되며, 리졸버가
// 블로킹 I/O를 수행하지만 자산 파일은 작을 것으로 예상되므로 Phase 5
// 수준에서는 허용 가능한 마지노섬이다.
@MainActor
internal final class KSMacSchemeHandler: NSObject, WKURLSchemeHandler {
    var resolver: KSAssetResolver?
    var csp: String = KSSecurityConfig.defaultCSP

    nonisolated func webView(
        _ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask
    ) {
        MainActor.assumeIsolated {
            self.startTask(urlSchemeTask)
        }
    }

    nonisolated func webView(
        _ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask
    ) {}

    private func startTask(_ task: any WKURLSchemeTask) {
        guard let url = task.request.url, let resolver else {
            task.didFailWithError(NSError(
                domain: "Kalsae", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "no resolver bound"]))
            return
        }
        let path = url.path
        do {
            let asset = try resolver.resolve(path: path)
            let headers: [String: String] = [
                "Content-Type": asset.mimeType,
                "Content-Length": String(asset.data.count),
                "Content-Security-Policy": csp,
            ]
            guard let response = HTTPURLResponse(
                url: url, statusCode: 200,
                httpVersion: "HTTP/1.1", headerFields: headers)
            else {
                task.didFailWithError(NSError(
                    domain: "Kalsae", code: 500))
                return
            }
            task.didReceive(response)
            task.didReceive(asset.data)
            task.didFinish()
        } catch {
            task.didFailWithError(NSError(
                domain: "Kalsae", code: 404,
                userInfo: [NSLocalizedDescriptionKey: String(describing: error)]))
        }
    }
}

/// Concrete WKScriptMessageHandler. Kept as a separate class to avoid
/// forcing the rest of the module to inherit from NSObject.
@MainActor
internal final class KSScriptMessageHandler: NSObject, WKScriptMessageHandler {
    internal var onMessage: (@MainActor (String) -> Void)?

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        // WKScriptMessageHandler 콜백은 문서상 메인 스레드에서 도착한다고
        // 되어 있지만, Swift 6 상 정확성을 위해 명시적으로 입고한다.
        let body = message.body
        MainActor.assumeIsolated {
            // 통일된 브리지 계약을 위해 JSON 문자열로 재직렬화한다.
            // Windows 쪽도 WebView2에서 JSON 텍스트를 받는다.
            let text: String
            if let s = body as? String {
                text = s
            } else if JSONSerialization.isValidJSONObject(body) {
                if let data = try? JSONSerialization.data(
                    withJSONObject: body, options: []),
                   let s = String(data: data, encoding: .utf8) {
                    text = s
                } else {
                    return
                }
            } else {
                return
            }
            self.onMessage?(text)
        }
    }
}
#endif
