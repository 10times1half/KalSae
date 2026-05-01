import Foundation

/// `__ks.http.*` 명령군에 대한 권한 범위. Tauri 스타일.
///
/// 네트워크 접근은 **기본 거부**다. 범위를 초기의 빈 값으로 두면
/// `__ks.http.fetch`는 모든 요청을 `KSError(.commandNotAllowed)`로 거부한다.
/// 앱은 신뢰하는 오리진 또는 URL 접두사를 명시적으로 추가해야 한다.
///
/// 허용/거부 항목은 다음 매칭 형태를 지원한다(대소문자 무시,
/// 적용 순서는 `deny` 먼저, `allow` 나중).
///   * 정확한 오리진: `"https://api.example.com"` — 호스트 + 스킴 + 포트가 모두 일치.
///   * 오리진 와일드카드: `"https://*.example.com"` — `example.com`의 모든 서브호스트.
///   * 전체 URL 접두사: `"https://api.example.com/v1/"` — URL이 이 접두사로 시작할 때만 허용.
///   * 스킴 전용: `"https://*"` — 해당 스킴을 사용하는 모든 URL.
public struct KSHTTPScope: Codable, Sendable, Equatable {
    /// 허용되는 오리진/URL 접두사 패턴.
    public var allow: [String]
    /// 거부되는 패턴. `allow`보다 **먼저** 평가된다.
    public var deny: [String]
    /// 허용되는 HTTP 메서드.
    /// 빈 배열은 "메서드 허용 없음", `nil`은 "`allow`/`deny` 외 추가 메서드 제한 없음"을 뜻한다.
    /// 비교는 대소문자를 구분하지 않는다.
    public var methods: [String]?
    /// `__ks.http.fetch`를 통해 나가는 모든 요청에 자동으로 붙는 헤더.
    /// JS 측이 보면 안 되는 OS 키체인 기반 `Authorization` 헤더 등에 유용하다.
    public var defaultHeaders: [String: String]

    public init(
        allow: [String] = [],
        deny: [String] = [],
        methods: [String]? = nil,
        defaultHeaders: [String: String] = [:]
    ) {
        self.allow = allow
        self.deny = deny
        self.methods = methods
        self.defaultHeaders = defaultHeaders
    }

    private enum CodingKeys: String, CodingKey {
        case allow, deny, methods, defaultHeaders
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.allow = try c.decodeIfPresent([String].self, forKey: .allow) ?? []
        self.deny = try c.decodeIfPresent([String].self, forKey: .deny) ?? []
        self.methods = try c.decodeIfPresent([String].self, forKey: .methods)
        self.defaultHeaders = try c.decodeIfPresent(
            [String: String].self, forKey: .defaultHeaders) ?? [:]
    }

    /// `urlString`이 이 범위에 의해 허용되면 `true`를 반환한다.
    /// 스킴과 호스트는 대소문자를 구분하지 않지만, 경로는 대소문자를 구분한다.
    /// 잘못된 URL은 절대 매칭되지 않는다.
    public func permits(urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        let normalized = Self.normalize(url: url)
        for pattern in deny {
            if Self.match(normalized: normalized, pattern: pattern) {
                return false
            }
        }
        for pattern in allow {
            if Self.match(normalized: normalized, pattern: pattern) {
                return true
            }
        }
        return false
    }

    /// `method`가 허용되면 `true`를 반환한다(대소문자 무시).
    public func permits(method: String) -> Bool {
        guard let methods else { return true }
        let lower = method.lowercased()
        return methods.contains { $0.lowercased() == lower }
    }

    // MARK: - 내부 매칭

    /// 스킴과 호스트를 소문자로 정규화한 뒤 비교 가능한 문자열을 다시 만든다.
    /// 경로는 대소문자를 유지한다.
    private static func normalize(url: URL) -> String {
        var s = ""
        if let scheme = url.scheme { s += scheme.lowercased() + "://" }
        if let host = url.host { s += host.lowercased() }
        if let port = url.port { s += ":\(port)" }
        s += url.path
        if let q = url.query { s += "?" + q }
        return s
    }

    private static func match(normalized: String, pattern: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return false }
        // 단일 와일드카드는 모든 URL 허용.
        if p == "*" || p == "*://*" { return true }
        // 스키마 분리. 스키마가 없으면 단순 접두사 매칭.
        guard let schemeEnd = p.range(of: "://") else {
            return normalized.hasPrefix(p)
        }
        let scheme = p[..<schemeEnd.lowerBound].lowercased()
        guard normalized.hasPrefix(scheme + "://") else { return false }
        let inputAfter = String(normalized.dropFirst(scheme.count + 3))
        let patternAfter = String(p[schemeEnd.upperBound...])

        // 호스트 와일드카드만(`*`)이면 매칭 종료.
        if patternAfter == "*" { return true }

        // 패턴/입력을 host와 path로 분리. host는 첫 `/` 이전.
        let (patternHost, patternPath) = splitHostPath(patternAfter)
        let (inputHost, inputPath) = splitHostPath(inputAfter)

        guard hostMatches(pattern: patternHost, input: inputHost) else {
            return false
        }
        // 패턴에 path가 없으면 어떤 입력 path도 허용.
        if patternPath.isEmpty { return true }
        // glob 메타문자가 있으면 KSFSScope.glob로 매칭.
        if patternPath.contains("*") || patternPath.contains("?") {
            return KSFSScope.glob(pattern: "/" + patternPath, matches: "/" + inputPath)
        }
        // 그렇지 않으면 단순 접두사 매칭(끝의 `/`는 prefix 의미).
        return ("/" + inputPath).hasPrefix("/" + patternPath)
    }

    /// `"host[:port]/path"`(또는 `"host[:port]"`)를 `(host, path)`로 분리한다.
    /// `path`에는 선행 슬래시가 포함되지 않는다.
    private static func splitHostPath(_ s: String) -> (host: String, path: String) {
        guard let slash = s.firstIndex(of: "/") else { return (s, "") }
        let host = String(s[..<slash])
        let path = String(s[s.index(after: slash)...])
        return (host, path)
    }

    /// 호스트 패턴을 입력 호스트와 비교한다.
    /// 타입 문서에 설명한 exact, `*`, `*.foo.com`, `host:port` 형태를 지원한다.
    private static func hostMatches(pattern: String, input: String) -> Bool {
        if pattern == "*" { return true }
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(1)) // ".foo.com[:port]"
            // 정확한 루트 호스트(서브도메인 없음): "foo.com"과 일치.
            if input == String(suffix.dropFirst()) { return true }
            // 서브도메인: ".foo.com"을 입력의 첫 점 이후 부분이 가져야 함.
            if input.hasSuffix(suffix) { return true }
            // 포트 등으로 입력에 추가 토큰이 붙는 경우 — host:port 형태에서는
            // pattern의 ':port'와 input의 ':port'가 정확히 일치해야 한다.
            return false
        }
        return pattern == input
    }
}

/// WebView 다운로드 이벤트(`ICoreWebView2.add_DownloadStarting`)에 대한 권한 범위.
///
/// `enabled`가 `false`이면(기본값, 즉 기본 거부) 페이지가 시작한 모든 다운로드를 취소한다.
/// `true`이면 다운로드를 허용하며, 호스트가 별도 진행 상황 싱크를 등록하지 않는 한
/// WebView2 기본 다운로드 UI가 이를 처리한다.
public struct KSDownloadScope: Codable, Sendable, Equatable {
    /// 다운로드 자체를 허용할지 여부.
    public var enabled: Bool
    /// 선택적 기본 디렉터리(절대 경로 또는 `$HOME` / `$DOCS` / `$APP` / `$TEMP` 플레이스홀더).
    /// 설정되면 런타임이 이 디렉터리를 WebView2 다운로드 UI에 제안한다.
    public var defaultDirectory: String?
    /// `true`이면 모든 다운로드마다 OS 네이티브 "다른 이름으로 저장" 대화상자를 띄운다.
    /// `false`이면 WebView2 기본 UI를 사용한다.
    public var promptUser: Bool

    public init(
        enabled: Bool = false,
        defaultDirectory: String? = nil,
        promptUser: Bool = true
    ) {
        self.enabled = enabled
        self.defaultDirectory = defaultDirectory
        self.promptUser = promptUser
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, defaultDirectory, promptUser
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.defaultDirectory = try c.decodeIfPresent(String.self, forKey: .defaultDirectory)
        self.promptUser = try c.decodeIfPresent(Bool.self, forKey: .promptUser) ?? true
    }
}

/// 모든 WebView 네비게이션(`ICoreWebView2.add_NavigationStarting`)에 강제되는
/// 오리진 허용 목록.
///
/// 허용 목록이 비어 있으면 네비게이션은 제한되지 않는다(기존 앱을 깨지 않는 레거시 동작).
/// 하나 이상 선언되면 목록 밖 URL로의 이동은 취소되고,
/// 스킴이 허용된 경우 `KSShellBackend.openExternal`로 우회하며,
/// 그렇지 않으면 버린다.
///
/// 패턴 형태는 `KSHTTPScope`와 동일하다.
public struct KSNavigationScope: Codable, Sendable, Equatable {
    /// 창 내부 네비게이션에 허용되는 오리진/URL 접두사 패턴.
    public var allow: [String]
    /// `true`이면(기본값) `allow` 검사를 통과하지 못했지만
    /// `KSShellScope.openExternalSchemes`에서 허용된 스킴을 쓰는 URL은
    /// OS 기본 핸들러로 연다. `false`이면 네비게이션을 조용히 버린다.
    public var openExternallyOnReject: Bool

    public init(allow: [String] = [], openExternallyOnReject: Bool = true) {
        self.allow = allow
        self.openExternallyOnReject = openExternallyOnReject
    }

    private enum CodingKeys: String, CodingKey {
        case allow, openExternallyOnReject
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.allow = try c.decodeIfPresent([String].self, forKey: .allow) ?? []
        self.openExternallyOnReject = try c.decodeIfPresent(
            Bool.self, forKey: .openExternallyOnReject) ?? true
    }

    /// `urlString`로의 네비게이션이 창 내부에서 허용되어야 하면 `true`를 반환한다.
    /// `allow` 목록이 비어 있으면 `true`를 반환한다(제한 없음).
    /// `KSHTTPScope`의 매칭 로직을 재사용한다.
    public func permits(urlString: String) -> Bool {
        if allow.isEmpty { return true }
        let stub = KSHTTPScope(allow: allow)
        return stub.permits(urlString: urlString)
    }
}
