/// `KSUserScript`의 본문을 IIFE로 감싸 다음을 강제하는 헬퍼.
///
/// 1. **Origin 가드** — `location.href`가 등록된 origin 패턴 중 어느 것과도
///    매칭되지 않으면 본문 실행을 건너뛴다. WKWebView/Android 등 네이티브 origin
///    필터가 부재하거나 빈약한 백엔드에서도 일관된 동작을 보장한다.
/// 2. **documentEnd 폴리필** — Windows WebView2와 Android WebView는 document-end
///    훅이 표준화되어 있지 않아, `DOMContentLoaded` 리스너로 시점을 맞춘다.
/// 3. **예외 격리** — 사용자 스크립트의 throw가 페이지 JS를 중단시키지 않도록
///    `try/catch`로 감싼다.
public enum KSUserScriptWrapper {
    /// 호스트에 실제로 등록할 최종 JS 문자열을 반환한다.
    /// 본문이 비어 있어도 호출자 측에서 source/path 검증을 마쳤다고 가정한다.
    public static func wrap(_ script: KSUserScript, source: String) -> String {
        let originsJSON = encodeJSONArray(script.origins)
        let injectionTimeJS = (script.injectionTime == .documentEnd) ? "documentEnd" : "documentStart"
        return """
            (function () {
              try {
                var __ks_origins = \(originsJSON);
                function __ks_hostMatches(pattern, host) {
                  if (pattern === "*") return true;
                  if (pattern.length > 2 && pattern.charCodeAt(0) === 42 && pattern.charCodeAt(1) === 46) {
                    var suffix = pattern.slice(1);
                    if (host === suffix.slice(1)) return true;
                    return host.length > suffix.length && host.slice(-suffix.length) === suffix;
                  }
                  return pattern === host;
                }
                function __ks_match(pattern, url) {
                  pattern = String(pattern || "").trim();
                  if (!pattern) return false;
                  if (pattern === "*" || pattern === "*://*") return true;
                  var sep = pattern.indexOf("://");
                  if (sep < 0) return url.indexOf(pattern) === 0;
                  var pScheme = pattern.slice(0, sep).toLowerCase();
                  var uSchemeEnd = url.indexOf("://");
                  if (uSchemeEnd < 0) return false;
                  if (url.slice(0, uSchemeEnd).toLowerCase() !== pScheme) return false;
                  var pRest = pattern.slice(sep + 3);
                  if (pRest === "*") return true;
                  var uRest = url.slice(uSchemeEnd + 3);
                  var pSlash = pRest.indexOf("/");
                  var uSlash = uRest.indexOf("/");
                  var pHost = pSlash < 0 ? pRest : pRest.slice(0, pSlash);
                  var uHost = uSlash < 0 ? uRest : uRest.slice(0, uSlash);
                  if (!__ks_hostMatches(pHost.toLowerCase(), uHost.toLowerCase())) return false;
                  if (pSlash < 0) return true;
                  var pPath = "/" + pRest.slice(pSlash + 1);
                  var uPath = uSlash < 0 ? "/" : "/" + uRest.slice(uSlash + 1);
                  if (pPath.indexOf("*") < 0 && pPath.indexOf("?") < 0) return uPath.indexOf(pPath) === 0;
                  var rx = "^" + pPath
                    .replace(/[.+^${}()|[\\]\\\\]/g, "\\\\$&")
                    .replace(/\\*\\*/g, "::DOUBLESTAR::")
                    .replace(/\\*/g, "[^/]*")
                    .replace(/::DOUBLESTAR::/g, ".*")
                    .replace(/\\?/g, ".") + "$";
                  return new RegExp(rx).test(uPath);
                }
                var __ks_url = location.href;
                var __ks_ok = false;
                for (var i = 0; i < __ks_origins.length; i++) {
                  if (__ks_match(__ks_origins[i], __ks_url)) { __ks_ok = true; break; }
                }
                if (!__ks_ok) return;
                var __ks_run = function () {
                  try {
            \(indent(source, by: "      "))
                  } catch (e) {
                    console.error("[Kalsae user script]", e);
                  }
                };
                if ("\(injectionTimeJS)" === "documentEnd" && document.readyState === "loading") {
                  document.addEventListener("DOMContentLoaded", __ks_run, { once: true });
                } else {
                  __ks_run();
                }
              } catch (e) {
                if (typeof console !== "undefined") console.error("[Kalsae user script wrapper]", e);
              }
            })();
            """
    }

    /// 사용자 본문 들여쓰기를 한 단계 추가해 IIFE 가독성을 유지한다.
    private static func indent(_ s: String, by prefix: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    /// `JSONSerialization`을 쓰지 않고 ASCII 안전한 JSON 배열 리터럴을 생성한다.
    /// 본문에 임베드되므로 `\u2028`/`\u2029`도 이스케이프해야 한다.
    private static func encodeJSONArray(_ values: [String]) -> String {
        let parts = values.map(encodeJSONString)
        return "[" + parts.joined(separator: ",") + "]"
    }

    private static func encodeJSONString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }
}
