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
        KSBootOrchestrator.cspInjectionScript(csp)
    }

    internal static func isDirectory(_ url: URL) -> Bool {
        KSBootOrchestrator.isDirectory(url)
    }

    /// Treat non-empty `http://` and `https://` URLs as remote dev-server origins.
    /// Empty strings and `about:blank` are treated as "no dev server configured".
    internal static func isRemoteURL(_ s: String) -> Bool {
        KSBootOrchestrator.isRemoteURL(s)
    }

    /// Best-effort reachability probe for a dev-server origin. Issues a single
    /// `HEAD` (falling back to `GET`) and returns whether *any* HTTP response
    /// was received within `timeout` seconds. Network errors, DNS failures, and
    /// timeouts all return `false` — even non-2xx responses count as
    /// "something is listening", which is enough to prefer the dev server.
    ///
    /// 동기 함수다 — `decideServingMode` 가 동기이므로 `DispatchSemaphore` 로
    /// 결과를 기다린다. `decideServingMode` 는 부팅 1회만 호출되므로 1.5s
    /// 정도의 가벼운 블로킹은 허용 가능하다.
    ///
    /// 타임아웃을 짧게(예: 250ms) 잡으면 Windows 의 Foundation URLSession
    /// 콜드 스타트(첫 호출 시 CFNetwork/libcurl 초기화)가 그 안에 끝나지
    /// 못해 `kalsae dev` 가 이미 vite reachability 를 확인한 직후에도 부팅
    /// 시점 probe 가 false 를 돌려주는 경우가 있다. 결과적으로 dev 서버를
    /// 두고 가상 호스트로 폴백 → React/Vue/Svelte 프리셋의 리소스 번들에는
    /// `index.html` 이 없어 흰 화면이 된다. 이를 막기 위해 1.5s 까지 기다린다.
    internal static func isDevServerReachable(
        _ urlString: String, timeout: TimeInterval = 1.5
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

    /// 가상 호스트도 없고 dev 서버도 응답하지 않는 폴백 상황에서 사용할
    /// `data:text/html` URL 을 만든다. WebView 가 `chrome-error://...` 흰 화면
    /// 대신 무엇이 일어났는지, 어떤 URL 을 시도했는지, 다음 단계가 무엇인지
    /// 즉시 보여줄 수 있다.
    ///
    /// `data:` 스킴은 자체 origin 이라 호스트 CSP 와 충돌하지 않는다. 정적
    /// 콘텐츠만 담고 인라인 스크립트를 쓰지 않으므로 보안 표면도 없다.
    internal static func diagnosticDataURL(attemptedURL: String) -> String {
        let safeURL = htmlEscape(attemptedURL)
        let html = """
            <!doctype html><html><head><meta charset="utf-8">\
            <title>Kalsae — frontend not available</title>\
            <style>\
            body{font:14px/1.5 system-ui,sans-serif;margin:2.5rem;color:#222;background:#fafafa}\
            h1{font-size:1.25rem;margin:0 0 .5rem}\
            code{background:#eee;padding:1px 5px;border-radius:3px;font-size:.95em}\
            ul{padding-left:1.25rem}\
            li{margin:.25rem 0}\
            .muted{color:#666;font-size:.9em;margin-top:1.5rem}\
            </style></head><body>\
            <h1>Kalsae: 프론트엔드를 불러올 수 없습니다</h1>\
            <p>가상 호스트 자산 디렉터리도 없고, 설정된 dev 서버도 응답하지 않아 \
            기본 페이지를 표시할 수 없습니다.</p>\
            <p>시도한 dev 서버: <code>\(safeURL)</code></p>\
            <h2 style="font-size:1rem;margin-top:1.5rem">다음 단계</h2>\
            <ul>\
            <li><code>kalsae build</code> 또는 <code>npm run build</code> 로 \
            <code>build.frontendDist</code> 디렉터리를 생성했는지 확인하세요.</li>\
            <li>개발 중이라면 dev 서버(예: <code>npm run dev</code>) 가 \
            지정된 주소에서 응답하는지 확인하세요.</li>\
            <li><code>kalsae.json</code> 의 <code>build.devServerURL</code> / \
            <code>build.frontendDist</code> 설정이 올바른지 확인하세요.</li>\
            </ul>\
            <p class="muted">This page is served as a <code>data:</code> URL by Kalsae \
            because no frontend source could be reached.</p>\
            </body></html>
            """
        // RFC 2397 - characters allowed: any printable except `#`, `%`, and
        // some others. Percent-encode minimally for safety.
        let allowed = CharacterSet.urlPathAllowed
            .union(.urlQueryAllowed)
            .union(CharacterSet(charactersIn: "<>\"' "))
        let encoded =
            html.addingPercentEncoding(withAllowedCharacters: allowed) ?? html
        return "data:text/html;charset=utf-8,\(encoded)"
    }

    /// 진단 페이지에 임의의 사용자 입력(시도 URL)을 넣을 때 쓰는 최소 HTML
    /// escaper. 외부 사용자 입력이 아닌 config 값이라 표면이 좁지만
    /// 방어적으로 둔다.
    private static func htmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }
}
