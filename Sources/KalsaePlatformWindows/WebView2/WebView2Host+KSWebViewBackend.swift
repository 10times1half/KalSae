#if os(Windows)
    internal import CKalsaeWV2
    internal import Logging
    internal import KalsaeCore
    internal import Foundation

    @MainActor
    extension WebView2Host: KSWebViewBackend {
        public func load(url: URL) async throws(KSError) {
            try navigate(url: url.absoluteString)
        }

        @discardableResult
        public func evaluateJavaScript(_ source: String) async throws(KSError) -> Data? {
            guard let webview = webviewPtr else {
                throw KSError(
                    code: .webviewInitFailed,
                    message: "WebView not initialized")
            }
            var hr: Int32 = 0
            source.withUTF16Pointer { ptr in
                hr = KSWV2_ExecuteScript(webview, ptr)
            }
            try KSHRESULT(hr).throwIfFailed(.webviewInitFailed, "ExecuteScript")
            return nil
        }

        public func postMessage(_ message: KSIPCMessage) async throws(KSError) {
            let data: Data
            do {
                data = try JSONEncoder().encode(message)
            } catch {
                throw KSError(
                    code: .internal,
                    message: "postMessage: JSON encoding failed (\(error))")
            }
            guard let json = String(data: data, encoding: .utf8) else {
                throw KSError(code: .internal, message: "postMessage: JSON encoding failed")
            }
            try postJSON(json)
        }

        public func setMessageHandler(
            _ handler: @Sendable @escaping (KSIPCMessage) async -> Void
        ) async {
            do {
                try onMessage { text in
                    guard let data = text.data(using: .utf8),
                        let msg = try? JSONDecoder().decode(KSIPCMessage.self, from: data)
                    else { return }
                    Task {
                        await handler(msg)
                    }
                }
            } catch {
                KSLog.logger("platform.windows.webview").warning(
                    "setMessageHandler install failed: \(error)")
            }
        }

        public func setContentSecurityPolicy(_ csp: String) async throws(KSError) {
            try addDocumentCreatedScript(Self.cspInjectionScript(csp))
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
