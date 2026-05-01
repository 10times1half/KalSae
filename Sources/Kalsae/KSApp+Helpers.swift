internal import Foundation

extension KSApp {

    /// 내장 자산 매핑에 사용되는 가상 호스트.
    public static let virtualHost = "app.kalsae"

    /// 가능한 가장 이른 시점에 CSP `<meta>` 태그를 설치하는 작은 JS 스니펫.
    /// 플랫폼 호스트가 엔진의 document-created 훅을 통해 등록하므로,
    /// HTML이 파싱되기 전에 실행된다.
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

    /// `http://…`와 `https://…`(`about:blank` 제외)를 라이브 dev 서버
    /// 엔드포인트로 간주한다. 빈 문자열과 `about:blank`는
    /// "dev 서버가 구성되지 않음"으로 해석된다.
    internal static func isRemoteURL(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.lowercased() == "about:blank" { return false }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }
}
