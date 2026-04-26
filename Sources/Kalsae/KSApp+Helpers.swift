internal import Foundation

extension KSApp {

    /// Virtual host used by the built-in asset mapping.
    public static let virtualHost = "app.kalsae"

    /// Small JS snippet that installs a CSP `<meta>` tag at the earliest
    /// possible moment. Platform hosts register it via the engine's
    /// document-created hook, so it runs before any HTML is parsed.
    internal static func cspInjectionScript(_ csp: String) -> String {
        // JS 리터럴에 안전하게 넣기 위해 따옴표와 역슬래시를 이스케이프한다.
        var escaped = ""
        escaped.reserveCapacity(csp.count + 8)
        for ch in csp {
            switch ch {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            default:   escaped.append(ch)
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

    /// Treats `http://…` and `https://…` (anything but `about:blank`) as
    /// a live dev server endpoint. Empty strings and `about:blank` are
    /// interpreted as "no dev server configured".
    internal static func isRemoteURL(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.lowercased() == "about:blank" { return false }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }
}
