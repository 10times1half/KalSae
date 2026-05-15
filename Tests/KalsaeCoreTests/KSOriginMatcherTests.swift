import Foundation
import Testing

@testable import KalsaeCore

// MARK: - KSOriginMatcher 단위 테스트
//
// Tauri 2의 capabilities `remote.urls` 매칭 규칙을 미러링한다.
// - 정확 일치, 와일드카드 호스트(서브도메인만), 와일드카드 스킴, 포트 비교.

@Suite("KSOriginMatcher — pattern rules")
struct KSOriginMatcherTests {

    @Test("정확 일치 origin은 매칭된다")
    func exactMatch() {
        #expect(
            KSOriginMatcher.matches(
                pattern: "https://example.com",
                origin: "https://example.com"))
    }

    @Test("스킴이 다르면 매칭되지 않는다")
    func schemeMismatch() {
        #expect(
            !KSOriginMatcher.matches(
                pattern: "https://example.com",
                origin: "http://example.com"))
    }

    @Test("`*.example.com` 와일드카드는 서브도메인만 매칭")
    func wildcardSubdomain() {
        #expect(
            KSOriginMatcher.matches(
                pattern: "https://*.example.com",
                origin: "https://api.example.com"))
        #expect(
            KSOriginMatcher.matches(
                pattern: "https://*.example.com",
                origin: "https://a.b.example.com"))
        // bare host는 제외.
        #expect(
            !KSOriginMatcher.matches(
                pattern: "https://*.example.com",
                origin: "https://example.com"))
    }

    @Test("`*://` 와일드카드 스킴")
    func wildcardScheme() {
        #expect(
            KSOriginMatcher.matches(
                pattern: "*://example.com",
                origin: "https://example.com"))
        #expect(
            KSOriginMatcher.matches(
                pattern: "*://example.com",
                origin: "http://example.com"))
    }

    @Test("호스트가 다르면 매칭되지 않는다")
    func hostMismatch() {
        #expect(
            !KSOriginMatcher.matches(
                pattern: "https://example.com",
                origin: "https://other.com"))
    }

    @Test("포트는 패턴에 명시될 때만 비교")
    func portRules() {
        // 패턴에 포트가 없으면 origin 포트는 무시.
        #expect(
            KSOriginMatcher.matches(
                pattern: "https://example.com",
                origin: "https://example.com:8443"))
        // 패턴에 포트가 있으면 일치해야 한다.
        #expect(
            KSOriginMatcher.matches(
                pattern: "https://example.com:8443",
                origin: "https://example.com:8443"))
        #expect(
            !KSOriginMatcher.matches(
                pattern: "https://example.com:8443",
                origin: "https://example.com:9000"))
    }

    @Test("호스트 비교는 대소문자를 구분하지 않는다")
    func hostCaseInsensitive() {
        #expect(
            KSOriginMatcher.matches(
                pattern: "https://EXAMPLE.com",
                origin: "https://example.COM"))
    }

    @Test("잘못된 origin은 매칭되지 않는다")
    func invalidOrigin() {
        #expect(
            !KSOriginMatcher.matches(
                pattern: "https://example.com",
                origin: "not a url"))
    }
}

// MARK: - KSCapability.matches(origin:) 통합 검증

@Suite("KSCapability — matches(origin:)")
struct KSCapabilityOriginMatchTests {

    @Test("origin이 nil이면 local 플래그를 따른다")
    func nilOriginLocal() {
        let local = KSCapability(
            identifier: "c", permissions: ["p"], local: true)
        #expect(local.matches(origin: nil))

        let nonLocal = KSCapability(
            identifier: "c", permissions: ["p"], local: false)
        #expect(!nonLocal.matches(origin: nil))
    }

    @Test("ks:// / file:// / about:blank 는 local로 간주")
    func localSchemes() {
        let cap = KSCapability(
            identifier: "c", permissions: ["p"], local: true)
        #expect(cap.matches(origin: "ks://app/index.html"))
        #expect(cap.matches(origin: "file:///tmp/index.html"))
        #expect(cap.matches(origin: "about:blank"))
        #expect(cap.matches(origin: "https://app.kalsae/"))
    }

    @Test("원격 origin은 remote.urls 패턴과 일치해야 매칭")
    func remoteMatching() {
        let cap = KSCapability(
            identifier: "c",
            permissions: ["p"],
            local: false,
            remote: KSRemoteOriginConfig(urls: ["https://*.example.com"]))
        #expect(cap.matches(origin: "https://api.example.com"))
        #expect(!cap.matches(origin: "https://example.com"))  // bare
        #expect(!cap.matches(origin: "https://other.com"))
    }

    @Test("remote 미설정이면 원격 origin은 거부")
    func remoteUnset() {
        let cap = KSCapability(
            identifier: "c", permissions: ["p"], local: false)
        #expect(!cap.matches(origin: "https://example.com"))
    }
}
