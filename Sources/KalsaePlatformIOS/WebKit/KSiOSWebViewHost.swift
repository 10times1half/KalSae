#if os(iOS)
    internal import UIKit
    internal import WebKit
    public import KalsaeCore
    public import Foundation

    // MARK: - ?怨???JS

    /// 筌뤴뫀諭??袁⑥쟿?袁⑸퓠 雅뚯눘???롫뮉 JavaScript. macOS ???삸??깆벥 `KSRuntimeJS`??    /// 沃섎챶??쭕???`webkit.messageHandlers` API??iOS?癒?퐣 ??덉뵬??롫뼄.
    private enum KSiOSRuntimeJS {
        static let source: String = #"""
                                    (function () {
                          if (window.__KS_) return;

                          const pending = new Map();
                          const listeners = new Map();
                          let nextId = 1;

                          function nativePost(obj) {
                            try {
                              window.webkit.messageHandlers.ks.postMessage(obj);
                            } catch (e) {
                              console.error('[KS] postMessage failed', e);
                            }
                          }

                          function handleInbound(msg) {
                            if (!msg || typeof msg !== 'object') return;
                            switch (msg.kind) {
                              case 'response': {
                                const p = pending.get(msg.id);
                                if (!p) return;
                                pending.delete(msg.id);
                                if (msg.isError) p.reject(msg.payload);
                                else p.resolve(msg.payload);
                                break;
                              }
                              case 'event': {
                                const set = listeners.get(msg.name);
                                if (!set) return;
                                for (const fn of set) {
                                  try { fn(msg.payload); } catch (e) { console.error(e); }
                                }
                                break;
                              }
                            }
                          }

                          const KB = Object.freeze({
                            invoke(cmd, args) {
                              return new Promise((resolve, reject) => {
                                const id = String(nextId++);
                                pending.set(id, { resolve, reject });
                                nativePost({
                                  kind: 'invoke',
                                  id,
                                  name: cmd,
                                  payload: args === undefined ? null : args,
                                });
                              });
                            },
                            listen(event, cb) {
                              if (typeof cb !== 'function') throw new TypeError('callback required');
                              let set = listeners.get(event);
                              if (!set) { set = new Set(); listeners.set(event, set); }
                              set.add(cb);
                              return () => set.delete(cb);
                            },
                            emit(event, payload) {
                              nativePost({
                                kind: 'event',
                                name: event,
                                payload: payload === undefined ? null : payload,
                              });
                            },
                          });

                          window.__KS_ = KB;
                          if (!window.Kalsae) window.Kalsae = KB;

                          window.__KS_receive = handleInbound;
                        })();
            """#
    }

    // MARK: - ?諛몃윮 ?紐꾨뮞??
    @MainActor
    public final class KSiOSWebViewHost {
        internal let webView: WKWebView
        private let userContentController: WKUserContentController
        private let messageHandler: KSiOSScriptMessageHandler
        private let schemeHandler: KSiOSSchemeHandler
        private var inbound: ((String) -> Void)?

        public init(label: String) {
            let ucc = WKUserContentController()
            self.userContentController = ucc
            self.messageHandler = KSiOSScriptMessageHandler()
            self.schemeHandler = KSiOSSchemeHandler()

            let config = WKWebViewConfiguration()
            config.userContentController = ucc
            config.setURLSchemeHandler(schemeHandler, forURLScheme: "ks")

            let runtimeScript = WKUserScript(
                source: KSiOSRuntimeJS.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            ucc.addUserScript(runtimeScript)

            self.webView = WKWebView(frame: .zero, configuration: config)
            self.webView.scrollView.bounces = false

            messageHandler.onMessage = { [weak self] text in
                self?.inbound?(text)
            }
            ucc.add(messageHandler, name: "ks")

            KSLog.logger("platform.ios.webview").info("WKWebView created (label=\(label))")
        }

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
                    KSLog.logger("platform.ios.webview")
                        .warning("evaluateJavaScript failed: \(err)")
                }
            }
        }

        public func setAssetRoot(_ root: URL) throws(KSError) {
            schemeHandler.resolver = KSAssetResolver(root: root)
        }

        public func addDocumentCreatedScript(_ script: String) throws(KSError) {
            let us = WKUserScript(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            userContentController.addUserScript(us)
        }

        public func openDevTools() throws(KSError) {
            // iOS?癒?퐣 Web Inspector???????롮젻筌?macOS??Safari + 疫꿸퀗由??醫듚먨첎? ?袁⑹뒄??롫뼄 ??no-op.
        }
    }

    // MARK: - KSWebViewBackend 餓Β??
    extension KSiOSWebViewHost: KSWebViewBackend {
        public func load(url: URL) async throws(KSError) {
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
        }

        @discardableResult
        public func evaluateJavaScript(_ source: String) async throws(KSError) -> Data? {
            do {
                return try await withCheckedThrowingContinuation {
                    (cont: CheckedContinuation<Data?, any Error>) in
                    webView.evaluateJavaScript(source) { result, error in
                        if let error {
                            cont.resume(throwing: error)
                            return
                        }
                        if let result, !(result is NSNull),
                            let data = try? JSONSerialization.data(withJSONObject: result)
                        {
                            cont.resume(returning: data)
                        } else {
                            cont.resume(returning: nil)
                        }
                    }
                }
            } catch {
                throw KSError(code: .internal, message: "evaluateJavaScript: \(error)")
            }
        }

        public func postMessage(_ message: KSIPCMessage) async throws(KSError) {
            let data = try JSONEncoder().encode(message)
            guard let json = String(data: data, encoding: .utf8) else {
                throw KSError(code: .internal, message: "postMessage: JSON encoding failed")
            }
            try postJSON(json)
        }

        public func setMessageHandler(
            _ handler: @Sendable @escaping (KSIPCMessage) async -> Void
        ) async {
            self.inbound = { [weak self] text in
                guard let data = text.data(using: .utf8),
                    let msg = try? JSONDecoder().decode(KSIPCMessage.self, from: data)
                else { return }
                Task { await handler(msg) }
                _ = self
            }
        }

        public func setContentSecurityPolicy(_ csp: String) async throws(KSError) {
            schemeHandler.csp = csp
        }

        public func setCrossOriginIsolation(_ enabled: Bool) {
            schemeHandler.crossOriginIsolation = enabled
        }

        public func openDevTools() async throws(KSError) {
            // iOS?癒?퐣 Web Inspector???⑤벀而?API嚥??????????용뼄.
        }
    }

    // MARK: - ks:// ??쎄땀 ?紐껊굶??
    @MainActor
    internal final class KSiOSSchemeHandler: NSObject, WKURLSchemeHandler {
        var resolver: KSAssetResolver?
        var csp: String = KSSecurityConfig.defaultCSP
        var crossOriginIsolation: Bool = false

        nonisolated func webView(
            _ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask
        ) {
            MainActor.assumeIsolated { self.startTask(urlSchemeTask) }
        }

        nonisolated func webView(
            _ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask
        ) {}

        private func startTask(_ task: any WKURLSchemeTask) {
            guard let url = task.request.url, let resolver else {
                task.didFailWithError(
                    NSError(
                        domain: "Kalsae", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "no resolver bound"]))
                return
            }
            do {
                let asset = try resolver.resolve(path: url.path)
                var headers: [String: String] = [
                    "Content-Type": asset.mimeType,
                    "Content-Length": String(asset.data.count),
                    "Content-Security-Policy": csp,
                ]
                if crossOriginIsolation {
                    headers["Cross-Origin-Opener-Policy"] = "same-origin"
                    headers["Cross-Origin-Embedder-Policy"] = "require-corp"
                    headers["Cross-Origin-Resource-Policy"] = "same-origin"
                }
                guard
                    let response = HTTPURLResponse(
                        url: url, statusCode: 200,
                        httpVersion: "HTTP/1.1", headerFields: headers)
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
                        domain: "Kalsae", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: String(describing: error)]))
            }
        }
    }

    // MARK: - ??쎄쾿?깆???筌롫뗄?놅쭪? ?紐껊굶??
    @MainActor
    internal final class KSiOSScriptMessageHandler: NSObject, WKScriptMessageHandler {
        internal var onMessage: (@MainActor (String) -> Void)?

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            let body = message.body
            MainActor.assumeIsolated {
                let text: String
                if let s = body as? String {
                    text = s
                } else if JSONSerialization.isValidJSONObject(body) {
                    if let data = try? JSONSerialization.data(withJSONObject: body),
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
