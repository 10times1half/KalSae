internal import Foundation

extension KSApp {

    /// ?댁옣 ?먯궛 留ㅽ븨???ъ슜?섎뒗 媛???몄뒪??
    public static let virtualHost = "app.kalsae"

    /// 媛?ν븳 媛???대Ⅸ ?쒖젏??CSP `<meta>` ?쒓렇瑜??ㅼ튂?섎뒗 ?묒? JS ?ㅻ땲??
    /// ?뚮옯???몄뒪?멸? ?붿쭊??document-created ?낆쓣 ?듯빐 ?깅줉?섎?濡?
    /// HTML???뚯떛?섍린 ?꾩뿉 ?ㅽ뻾?쒕떎.
    internal static func cspInjectionScript(_ csp: String) -> String {
        // JS 由ы꽣?댁뿉 ?덉쟾?섍쾶 ?ｊ린 ?꾪빐 ?곗샂?쒖? ??뒳?섏떆瑜??댁뒪耳?댄봽?쒕떎.
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

    /// `http://??? `https://??(`about:blank` ?쒖쇅)瑜??쇱씠釉?dev ?쒕쾭
    /// ?붾뱶?ъ씤?몃줈 媛꾩＜?쒕떎. 鍮?臾몄옄?닿낵 `about:blank`??    /// "dev ?쒕쾭媛 援ъ꽦?섏? ?딆쓬"?쇰줈 ?댁꽍?쒕떎.
    internal static func isRemoteURL(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.lowercased() == "about:blank" { return false }
        let lower = trimmed.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }
}
