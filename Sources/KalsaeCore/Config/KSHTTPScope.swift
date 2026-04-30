import Foundation

/// Permission scope for the `__ks.http.*` command family. Tauri-style.
///
/// Network access is **deny-by-default**: when the scope is left at its
/// initial empty value, `__ks.http.fetch` rejects every request with
/// `KSError(.commandNotAllowed)`. Apps must explicitly add origins or
/// URL prefixes they trust.
///
/// Allow / deny entries support the following match shapes (case-insensitive,
/// applied in order: `deny` first, `allow` second):
///   * Exact origin: `"https://api.example.com"` — host + scheme + port match.
///   * Origin wildcard: `"https://*.example.com"` — any sub-host of `example.com`.
///   * Full URL prefix: `"https://api.example.com/v1/"` — only requests whose
///     URL starts with this prefix are admitted.
///   * Scheme-only: `"https://*"` — any URL using the given scheme.
public struct KSHTTPScope: Codable, Sendable, Equatable {
    /// Origin / URL prefix patterns that are allowed.
    public var allow: [String]
    /// Patterns that are denied. Evaluated **before** `allow`.
    public var deny: [String]
    /// HTTP methods permitted. Empty array means "no methods", `nil`
    /// means "no method restriction beyond `allow`/`deny`". Comparison
    /// is case-insensitive.
    public var methods: [String]?
    /// Headers automatically attached to every request issued through
    /// `__ks.http.fetch`. Useful for an `Authorization` header backed by
    /// an OS keychain that the JS side should not see.
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

    /// Returns `true` when `urlString` is admitted by this scope.
    /// Matching is case-insensitive on scheme and host but case-sensitive
    /// on path. An invalid URL never matches.
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

    /// Returns `true` when `method` is permitted (case-insensitive).
    public func permits(method: String) -> Bool {
        guard let methods else { return true }
        let lower = method.lowercased()
        return methods.contains { $0.lowercased() == lower }
    }

    // MARK: - Internal matching

    /// Lowercases the scheme + host components and rebuilds a comparable
    /// string. Path stays case-sensitive.
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

    /// Splits `"host[:port]/path"` (or `"host[:port]"`) into `(host, path)`.
    /// `path` excludes the leading slash.
    private static func splitHostPath(_ s: String) -> (host: String, path: String) {
        guard let slash = s.firstIndex(of: "/") else { return (s, "") }
        let host = String(s[..<slash])
        let path = String(s[s.index(after: slash)...])
        return (host, path)
    }

    /// Matches a host pattern against an input host. Supports the
    /// shapes documented in the type doc: exact, `*`, `*.foo.com`,
    /// `host:port`.
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

/// Permission scope for WebView download events
/// (`ICoreWebView2.add_DownloadStarting`).
///
/// When `enabled` is `false` (default — deny-by-default), all download
/// attempts initiated by the page are cancelled. When `true`, downloads
/// are admitted; the WebView2 default download UI handles them unless
/// the host registers its own progress sink.
public struct KSDownloadScope: Codable, Sendable, Equatable {
    /// Whether downloads are permitted at all.
    public var enabled: Bool
    /// Optional default directory (absolute path or `$HOME` / `$DOCS`
    /// / `$APP` / `$TEMP` placeholder). When set, the runtime suggests
    /// this directory to the WebView2 download UI.
    public var defaultDirectory: String?
    /// When `true`, the OS-native "save as" dialog is shown for every
    /// download. When `false`, the WebView2 default UI is used.
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

/// Origin allowlist enforced on every WebView navigation
/// (`ICoreWebView2.add_NavigationStarting`).
///
/// When the allow list is empty, navigation is unrestricted (legacy
/// behaviour — does not break existing apps). When at least one entry
/// is declared, navigation to URLs outside the list is cancelled and
/// re-routed through `KSShellBackend.openExternal` if the scheme is
/// permitted, otherwise dropped.
///
/// Patterns use the same shapes as `KSHTTPScope`.
public struct KSNavigationScope: Codable, Sendable, Equatable {
    /// Origin / URL prefix patterns admitted for in-window navigation.
    public var allow: [String]
    /// When `true` (default), URLs that fail the `allow` test but use a
    /// scheme permitted by `KSShellScope.openExternalSchemes` are opened
    /// via the OS default handler. When `false`, the navigation is
    /// silently dropped.
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

    /// Returns `true` when navigation to `urlString` should be admitted
    /// inside the window. An empty `allow` list returns `true` (no
    /// restriction). Reuses `KSHTTPScope`'s match logic.
    public func permits(urlString: String) -> Bool {
        if allow.isEmpty { return true }
        let stub = KSHTTPScope(allow: allow)
        return stub.permits(urlString: urlString)
    }
}
