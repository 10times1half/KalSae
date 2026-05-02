#if os(macOS)
    internal import AppKit
    internal import WebKit
    internal import Logging
    public import KalsaeCore
    public import Foundation

    @MainActor
    public final class WKWebViewHost: KSWebViewBackend {
        internal let webView: WKWebView
        private let userContentController: WKUserContentController
        private let log: Logger = KSLog.logger("platform.mac.webview")
        private var inbound: ((String) -> Void)?
        private var ipcHandler: (@Sendable (KSIPCMessage) async -> Void)?
        private let messageHandler: KSScriptMessageHandler
        private let schemeHandler: KSMacSchemeHandler
        private var closeInterceptorEnabled = false
        private var zoomFactor: Double = 1.0

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
            let userScript = WKUserScript(
                source: KSRuntimeJS.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            ucc.addUserScript(userScript)

            self.webView = WKWebView(frame: .zero, configuration: config)
            self.webView.autoresizingMask = [.width, .height]

            messageHandler.onMessage = { [weak self] text in
                self?.inbound?(text)
            }
            ucc.add(messageHandler, name: "ks")

            log.info("WKWebView created (label=\(label))")
        }

        // MARK: - KSWebViewBackend

        public func load(url: URL) async throws(KSError) {
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
        }

        @discardableResult
        public func evaluateJavaScript(_ source: String) async throws(KSError) -> Data? {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data?, any Error>) in
                webView.evaluateJavaScript(source) { result, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    if let result, !(result is NSNull) {
                        if let data = try? JSONSerialization.data(withJSONObject: result, options: []) {
                            cont.resume(returning: data)
                        } else {
                            cont.resume(returning: nil)
                        }
                    } else {
                        cont.resume(returning: nil)
                    }
                }
            }
        }

        public func postMessage(_ message: KSIPCMessage) async throws(KSError) {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            guard let json = String(data: data, encoding: .utf8) else {
                throw KSError(code: .internal, message: "postMessage: JSON encoding failed")
            }
            try postJSON(json)
        }

        public func setMessageHandler(_ handler: @Sendable @escaping (KSIPCMessage) async -> Void) async {
            self.ipcHandler = handler
        }

        public func setContentSecurityPolicy(_ csp: String) async throws(KSError) {
            schemeHandler.csp = csp
        }

        public func openDevTools() throws(KSError) {
            if #available(macOS 13.3, *) {
                webView.isInspectable = true
                log.info("WKWebView isInspectable = true")
            } else {
                log.warning("Web Inspector requires macOS 13.3+")
            }
        }

        // MARK: - 레거시 브리지 인터페이스

        public func onMessage(_ handler: @escaping @MainActor (String) -> Void) throws(KSError) {
            self.inbound = handler
        }

        public func navigate(url: String) throws(KSError) {
            guard let u = URL(string: url) else {
                throw KSError(code: .webviewInitFailed, message: "Invalid URL: \(url)")
            }
            if u.isFileURL {
                webView.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: u))
            }
        }

        public func postJSON(_ json: String) throws(KSError) {
            let script = "window.__KS_receive(\(json));"
            webView.evaluateJavaScript(script) { _, err in
                if let err {
                    KSLog.logger("platform.mac.webview")
                        .warning("evaluateJavaScript failed: \(err)")
                }
            }
        }

        public func setAssetRoot(_ root: URL) throws(KSError) {
            schemeHandler.resolver = KSAssetResolver(root: root)
        }

        public func addDocumentCreatedScript(_ script: String) throws(KSError) {
            let us = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(us)
        }

        // MARK: - 확장 PAL 인터페이스

        public func setBackgroundColor(_ color: NSColor) {
            webView.setValue(false, forKey: "drawsBackground")
            webView.setValue(color, forKey: "backgroundColor")
        }

        public func setCloseInterceptor(_ enabled: Bool) {
            closeInterceptorEnabled = enabled
        }

        public var isCloseInterceptorEnabled: Bool { closeInterceptorEnabled }

        public func emitBeforeCloseEvent() {
            webView.evaluateJavaScript(
                "if(window.__KS_)window.__KS_.emit('__ks.window.beforeClose',null);"
            ) { _, _ in }
        }

        public func setZoomFactor(_ factor: Double) {
            let clamped = min(max(factor, 0.5), 5.0)
            zoomFactor = clamped
            webView.evaluateJavaScript("document.body.style.zoom = '\(clamped)'") { _, _ in }
        }

        public func getZoomFactor() -> Double {
            zoomFactor
        }

        public func showPrintUI(systemDialog: Bool) {
            let printInfo = NSPrintInfo.shared
            let printOp = NSPrintOperation(view: webView, printInfo: printInfo)
            printOp.showsPrintPanel = systemDialog
            printOp.run()
        }

        public func capturePreview(format: Int32) async throws(KSError) -> Data {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, any Error>) in
                let config = WKSnapshotConfiguration()
                webView.takeSnapshot(with: config) { image, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    guard let image else {
                        cont.resume(throwing: KSError(code: .internal, message: "capturePreview: nil image"))
                        return
                    }
                    let format: NSBitmapImageRep.FileType = format == 1 ? .jpeg : .png
                    let props: [NSBitmapImageRep.PropertyKey: Any] =
                        format == 1
                        ? [.compressionFactor: 0.9]
                        : [:]
                    if let data = image.representations.first as? NSBitmapImageRep {
                        if let bytes = data.representation(using: format, properties: props) {
                            cont.resume(returning: bytes)
                            return
                        }
                    }
                    if let tiff = image.tiffRepresentation,
                        let rep = NSBitmapImageRep(data: tiff),
                        let bytes = rep.representation(using: format, properties: props)
                    {
                        cont.resume(returning: bytes)
                        return
                    }
                    cont.resume(throwing: KSError(code: .internal, message: "capturePreview: could not encode image"))
                }
            }
        }
    }

    // MARK: - ks:// 스킴 핸들러

    @MainActor
    internal final class KSMacSchemeHandler: NSObject, WKURLSchemeHandler {
        var resolver: KSAssetResolver?
        var csp: String = KSSecurityConfig.defaultCSP

        nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            MainActor.assumeIsolated { self.startTask(urlSchemeTask) }
        }

        nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

        private func startTask(_ task: any WKURLSchemeTask) {
            guard let url = task.request.url, let resolver else {
                task.didFailWithError(
                    NSError(domain: "Kalsae", code: 404, userInfo: [NSLocalizedDescriptionKey: "no resolver bound"]))
                return
            }
            do {
                let asset = try resolver.resolve(path: url.path)
                let headers: [String: String] = [
                    "Content-Type": asset.mimeType,
                    "Content-Length": String(asset.data.count),
                    "Content-Security-Policy": csp,
                    "X-Content-Type-Options": "nosniff",
                    "Referrer-Policy": "no-referrer",
                ]
                guard
                    let response = HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)
                else {
                    task.didFailWithError(NSError(domain: "Kalsae", code: 500))
                    return
                }
                task.didReceive(response)
                task.didReceive(asset.data)
                task.didFinish()
            } catch {
                task.didFailWithError(
                    NSError(
                        domain: "Kalsae", code: 404, userInfo: [NSLocalizedDescriptionKey: String(describing: error)]))
            }
        }
    }

    @MainActor
    internal final class KSScriptMessageHandler: NSObject, WKScriptMessageHandler {
        internal var onMessage: (@MainActor (String) -> Void)?

        nonisolated func userContentController(
            _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            let body = message.body
            MainActor.assumeIsolated {
                let text: String
                if let s = body as? String {
                    text = s
                } else if JSONSerialization.isValidJSONObject(body) {
                    if let data = try? JSONSerialization.data(withJSONObject: body, options: []),
                        let s = String(data: data, encoding: .utf8)
                    {
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
