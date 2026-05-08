internal import Foundation
#if canImport(FoundationNetworking)
    internal import FoundationNetworking
#endif

extension KSApp {

    /// Virtual host used when serving local assets.
    public static let virtualHost = "app.kalsae"

    /// Returns a script that injects a CSP `<meta>` tag as early as possible.
    /// Platform hosts register this as a document-created script so it runs
    /// before page HTML parsing completes.
    internal static func cspInjectionScript(_ csp: String) -> String {
        // Escape control characters so the value is safe inside a JS string literal.
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

    internal static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Treat non-empty `http://` and `https://` URLs as remote dev-server origins.
    /// Empty strings and `about:blank` are treated as "no dev server configured".
    internal static func isRemoteURL(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.lowercased() == "about:blank" { return false }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// Best-effort reachability probe for a dev-server origin. Issues a single
    /// `HEAD` (falling back to `GET`) and returns whether *any* HTTP response
    /// was received within `timeout` seconds. Network errors, DNS failures, and
    /// timeouts all return `false` — even non-2xx responses count as
    /// "something is listening", which is enough to prefer the dev server.
    ///
    /// 동기 함수다 — `decideServingMode` 가 동기이므로 `DispatchSemaphore` 로
    /// 결과를 기다린다. `decideServingMode` 는 부팅 1회만 호출되므로 200ms
    /// 정도의 가벼운 블로킹은 허용 가능하다.
    internal static func isDevServerReachable(
        _ urlString: String, timeout: TimeInterval = 0.25
    ) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "HEAD"

        let semaphore = DispatchSemaphore(value: 0)
        // `nonisolated(unsafe)` so a single-shot mutation inside the URLSession
        // delegate queue is reachable here without crossing isolation boundaries.
        nonisolated(unsafe) var ok = false
        let task = session.dataTask(with: req) { _, response, error in
            if error == nil, response is HTTPURLResponse {
                ok = true
            }
            semaphore.signal()
        }
        task.resume()
        // 약간의 슬랙(50ms)을 더해 URLSession 내부 스케줄 지연을 흡수.
        _ = semaphore.wait(timeout: .now() + timeout + 0.05)
        if !ok { task.cancel() }
        return ok
    }
}
