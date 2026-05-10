#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSDeepLinkBackend 계약

    @Suite("KSiOSDeepLinkBackend — unit contract")
    struct KSiOSDeepLinkBackendTests {

        let backend = KSiOSDeepLinkBackend(identifier: "com.example.kalsae-ios-test")

        @Test("register throws unsupportedPlatform (runtime registration not possible)")
        func registerThrows() {
            do {
                try backend.register(scheme: "myapp")
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("isRegistered returns false for unknown scheme")
        func isRegisteredFalseForUnknown() {
            // 테스트 번들에는 CFBundleURLTypes가 없으므로 항상 false.
            #expect(!backend.isRegistered(scheme: "myapp-unknown-\(UUID().uuidString)"))
        }

        @Test("extractURLs filters by scheme")
        func extractURLsFilters() {
            let args = ["myapp://open?id=1", "otherap://nope", "not-a-url", "myapp://open?id=2"]
            let urls = backend.extractURLs(fromArgs: args, forSchemes: ["myapp"])
            #expect(urls.count == 2)
            #expect(urls.allSatisfy { $0.hasPrefix("myapp://") })
        }

        @Test("currentLaunchURLs filters CommandLine args by scheme")
        func currentLaunchURLsFilters() {
            // CommandLine.arguments는 테스트 실행기 인자 — 스킴이 없으면 빈 배열 반환.
            let urls = backend.currentLaunchURLs(forSchemes: ["myapp-ks-test"])
            #expect(urls.isEmpty)
        }
    }
#endif
