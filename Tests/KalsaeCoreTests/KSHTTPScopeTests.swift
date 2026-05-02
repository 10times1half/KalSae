import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSHTTPScope")
struct KSHTTPScopeTests {
    @Test("Empty allow list rejects every URL (deny by default)")
    func denyByDefault() {
        let scope = KSHTTPScope()
        #expect(!scope.permits(urlString: "https://example.com"))
        #expect(!scope.permits(urlString: "https://api.example.com/v1/users"))
    }

    @Test("Exact origin allow")
    func exactOrigin() {
        let scope = KSHTTPScope(allow: ["https://api.example.com"])
        #expect(scope.permits(urlString: "https://api.example.com"))
        #expect(scope.permits(urlString: "https://api.example.com/v1"))
        #expect(!scope.permits(urlString: "http://api.example.com"))
        #expect(!scope.permits(urlString: "https://other.example.com"))
    }

    @Test("Subdomain wildcard")
    func subdomainWildcard() {
        let scope = KSHTTPScope(allow: ["https://*.example.com"])
        #expect(scope.permits(urlString: "https://api.example.com/v1"))
        #expect(scope.permits(urlString: "https://example.com/v1"))
        #expect(!scope.permits(urlString: "https://example.org"))
        #expect(!scope.permits(urlString: "http://api.example.com"))
    }

    @Test("Path prefix matching is case-sensitive")
    func pathPrefix() {
        let scope = KSHTTPScope(allow: ["https://api.example.com/v1/"])
        #expect(scope.permits(urlString: "https://api.example.com/v1/users"))
        #expect(!scope.permits(urlString: "https://api.example.com/v2/users"))
    }

    @Test("Deny is evaluated before allow")
    func denyBeforeAllow() {
        let scope = KSHTTPScope(
            allow: ["https://*.example.com"],
            deny: ["https://internal.example.com"])
        #expect(scope.permits(urlString: "https://api.example.com"))
        #expect(!scope.permits(urlString: "https://internal.example.com"))
    }

    @Test("Method gating")
    func methodGating() {
        let any = KSHTTPScope()
        #expect(any.permits(method: "GET"))
        #expect(any.permits(method: "POST"))
        let limited = KSHTTPScope(methods: ["GET", "HEAD"])
        #expect(limited.permits(method: "get"))
        #expect(limited.permits(method: "HEAD"))
        #expect(!limited.permits(method: "POST"))
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let scope = KSHTTPScope(
            allow: ["https://*.example.com"],
            deny: ["https://internal.example.com"],
            methods: ["GET", "POST"],
            defaultHeaders: ["X-App": "kalsae"])
        let data = try JSONEncoder().encode(scope)
        let decoded = try JSONDecoder().decode(KSHTTPScope.self, from: data)
        #expect(decoded == scope)
    }

    @Test("Decoding from minimal JSON applies defaults")
    func decodeMinimal() throws {
        let json = Data("{}".utf8)
        let scope = try JSONDecoder().decode(KSHTTPScope.self, from: json)
        #expect(scope.allow.isEmpty)
        #expect(scope.deny.isEmpty)
        #expect(scope.methods == nil)
        #expect(scope.defaultHeaders.isEmpty)
    }
}
@Suite("KSNavigationScope")
struct KSNavigationScopeTests {
    @Test("Empty allow list permits everything (no restriction)")
    func emptyAllowsAll() {
        let scope = KSNavigationScope()
        #expect(scope.permits(urlString: "https://anywhere.example.com"))
    }

    @Test("Non-empty allow list enforces match")
    func nonEmptyAllowEnforces() {
        let scope = KSNavigationScope(allow: ["http://localhost:5173/**"])
        #expect(scope.permits(urlString: "http://localhost:5173/index.html"))
        #expect(!scope.permits(urlString: "https://example.com"))
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let scope = KSNavigationScope(
            allow: ["ks://localhost/**"],
            openExternallyOnReject: false)
        let data = try JSONEncoder().encode(scope)
        let decoded = try JSONDecoder().decode(KSNavigationScope.self, from: data)
        #expect(decoded == scope)
    }
}
@Suite("KSDownloadScope")
struct KSDownloadScopeTests {
    @Test("Default scope is disabled (deny by default)")
    func defaultDisabled() {
        let scope = KSDownloadScope()
        #expect(!scope.enabled)
        #expect(scope.promptUser)
        #expect(scope.defaultDirectory == nil)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let scope = KSDownloadScope(
            enabled: true,
            defaultDirectory: "$DOCS/Downloads",
            promptUser: false)
        let data = try JSONEncoder().encode(scope)
        let decoded = try JSONDecoder().decode(KSDownloadScope.self, from: data)
        #expect(decoded == scope)
    }
}
