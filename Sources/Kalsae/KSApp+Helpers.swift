internal import Foundation

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
}
