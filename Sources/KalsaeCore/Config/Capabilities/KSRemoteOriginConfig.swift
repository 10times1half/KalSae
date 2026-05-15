public import Foundation

/// `KSCapability`가 원격(remote) 컨텐츠(예: 외부 사이트)로부터 IPC 호출을
/// 허용할 때 매칭되는 origin URL 패턴 묶음.
///
/// Tauri 2의 `capabilities/*.json`에 있는 `remote: { urls: [...] }`에
/// 대응한다. `urls` 의 각 항목은 다음 규칙으로 호출 origin과 비교된다.
///
/// - 정확 일치: `"https://example.com"` 은 동일 origin만 허용.
/// - 와일드카드 호스트: `"https://*.example.com"` 은 `example.com`의
///   서브도메인 전부를 허용한다(자기 자신은 미포함).
/// - 와일드카드 스킴: `"*://example.com"` 은 모든 스킴 허용.
/// - 포트는 패턴에 명시된 경우에만 일치하는 것으로 본다.
///
/// 패턴 비교는 `KSCapability.matches(origin:)` 가 수행하며, 호스트 비교는
/// 소문자 변환 후 진행한다.
public struct KSRemoteOriginConfig: Codable, Sendable, Equatable {
    /// 매칭에 사용할 origin URL 패턴 목록. 비어 있으면 어떤 원격 origin도
    /// 매칭되지 않는다(= 사실상 원격 비활성화).
    public var urls: [String]

    public init(urls: [String] = []) {
        self.urls = urls
    }

    private enum CodingKeys: String, CodingKey {
        case urls
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.urls = try c.decodeIfPresent([String].self, forKey: .urls) ?? []
    }
}

/// origin URL 문자열을 `(scheme, host, port?)` 로 정규화한 단순 표현.
/// 매칭에만 사용되므로 path / query / fragment 는 의도적으로 무시한다.
internal struct KSOriginParts: Equatable {
    let scheme: String  // 소문자
    let host: String  // 소문자
    let port: Int?  // 명시되지 않으면 nil

    init?(string: String) {
        // URL 파서에 의존해 잘못된 origin은 거른다. 단, `*://...` 처럼
        // 패턴 측 와일드카드는 별도 처리하므로 호출측이 책임진다.
        guard let url = URL(string: string), let scheme = url.scheme, let host = url.host else {
            return nil
        }
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        self.port = url.port
    }
}

/// 임의의 `URL` 또는 URL 문자열에서 origin 표현(`"scheme://host[:port]"`)을
/// 추출하는 헬퍼. PAL 브리지가 WebView의 현재 URL을 정책 평가기로 전달할 때
/// 사용한다. 호스트 없는 URL(`about:blank`, `data:` 등)은 그대로 반환한다.
public enum KSOrigin {
    /// `URL`에서 origin 문자열을 추출한다. scheme + host(+optional port) 만 보존.
    public static func string(from url: URL) -> String {
        guard let scheme = url.scheme else { return url.absoluteString }
        guard let host = url.host, !host.isEmpty else {
            // `about:blank`, `data:`, `javascript:` 등 호스트가 없는 URL.
            return url.absoluteString.lowercased()
        }
        if let port = url.port {
            return "\(scheme.lowercased())://\(host.lowercased()):\(port)"
        }
        return "\(scheme.lowercased())://\(host.lowercased())"
    }

    /// URL 문자열 표현을 origin으로 정규화. 파싱 실패 시 `nil`.
    public static func string(fromString s: String) -> String? {
        guard let url = URL(string: s) else { return nil }
        return string(from: url)
    }
}

/// origin 매칭 헬퍼. 패턴과 실제 origin을 KSOriginParts로 정규화한 뒤
/// 스킴/호스트/포트를 비교한다. 본 타입은 KalsaeCore 내부 구현 디테일이다.
internal enum KSOriginMatcher {
    /// 패턴이 origin과 매칭되는지 검사한다.
    static func matches(pattern: String, origin: String) -> Bool {
        // 패턴 측 와일드카드 스킴 처리: "*://host" → 임시로 "http://" 로
        // 치환해 파서를 통과시키고, 스킴 비교 단계에서 와일드카드를 인식.
        let patternIsAnyScheme = pattern.hasPrefix("*://")
        let normalizedPattern: String =
            patternIsAnyScheme ? "http://" + pattern.dropFirst("*://".count) : pattern

        guard let pat = KSOriginParts(string: normalizedPattern) else { return false }
        guard let org = KSOriginParts(string: origin) else { return false }

        // 스킴 비교 (와일드카드면 통과).
        if !patternIsAnyScheme && pat.scheme != org.scheme {
            return false
        }
        // 호스트 비교. 패턴이 `*.foo.com` 형태면 서브도메인 매칭.
        if pat.host.hasPrefix("*.") {
            let suffix = String(pat.host.dropFirst("*.".count))
            // 정확 일치(suffix 자신)는 제외 — Tauri 의미와 동일.
            guard org.host.hasSuffix("." + suffix) else { return false }
        } else if pat.host != org.host {
            return false
        }
        // 포트는 패턴에 명시된 경우에만 비교.
        if let p = pat.port, p != org.port {
            return false
        }
        return true
    }
}
