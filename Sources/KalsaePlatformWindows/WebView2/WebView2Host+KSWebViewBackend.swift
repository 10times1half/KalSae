#if os(Windows)
    internal import CKalsaeWV2
    internal import Logging
    internal import KalsaeCore
    internal import Foundation

    private let _wv2KSPostEncoder = JSONEncoder()
    @MainActor
    extension WebView2Host: KSWebViewBackend {
        /// URL을 WebView2로 로드한다.
        public func load(url: URL) async throws(KSError) {
            try navigate(url: url.absoluteString)
        }

        /// JavaScript 문자열을 WebView2에서 동기로 실행한다.
        /// 반환값(Data?)은 WebView2의 ExecuteScript 완료 콜백을 통해
        /// 비동기로 돌아오지만, 현재 구현은 콜백을 기다리지 않는다.
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

        /// `KSIPCMessage`를 JSON으로 인코딩해 WebView2 JS 측에 포스트한다.
        public func postMessage(_ message: KSIPCMessage) async throws(KSError) {
            let data: Data
            do {
                data = try _wv2KSPostEncoder.encode(message)
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

        /// WebView2의 `WebMessageReceived` 이벤트를 수신해
        /// JSON → `KSIPCMessage`로 디코딩한 후 `handler`로 전달한다.
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

        /// CSP 문자열을 `<meta http-equiv="Content-Security-Policy">` 태그로
        /// 문서 시작 시점에 주입한다.
        public func setContentSecurityPolicy(_ csp: String) async throws(KSError) {
            try addDocumentCreatedScript(Self.cspInjectionScript(csp))
        }

        /// CSP `<meta>` 태그 주입용 JavaScript 문자열을 생성한다.
        /// 특수 문자 (역슬래시, 따옴표, 개행 등)를 JS 문자열 리터럴에
        /// 안전하게 이스케이프한다.
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
