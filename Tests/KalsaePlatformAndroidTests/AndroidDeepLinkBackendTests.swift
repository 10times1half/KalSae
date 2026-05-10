#if os(Android)
    import Testing
    import Foundation
    @testable import KalsaePlatformAndroid
    import KalsaeCore

    // MARK: - KSAndroidDeepLinkBackend

    @Suite("KSAndroidDeepLinkBackend — URL extraction")
    struct KSAndroidDeepLinkBackendTests {

        @Test("register throws unsupportedPlatform")
        func registerThrows() {
            let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
            do {
                try backend.register(scheme: "myapp")
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("unregister throws unsupportedPlatform")
        func unregisterThrows() {
            let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
            do {
                try backend.unregister(scheme: "myapp")
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("extractURLs returns matching scheme URLs")
        func extractURLs() {
            let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
            let args = ["myapp://open?id=1", "https://example.com", "other://foo", "notaurl"]
            let result = backend.extractURLs(fromArgs: args, forSchemes: ["myapp"])
            #expect(result == ["myapp://open?id=1"])
        }

        @Test("extractURLs is case-insensitive on scheme")
        func extractURLsCaseInsensitive() {
            let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
            let args = ["MYAPP://open?id=2"]
            let result = backend.extractURLs(fromArgs: args, forSchemes: ["myapp"])
            #expect(result == ["MYAPP://open?id=2"])
        }

        @Test("isRegistered returns false without knownSchemes populated")
        func isRegisteredFalse() {
            KSAndroidDeepLinkBackend.knownSchemes = []
            let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
            #expect(backend.isRegistered(scheme: "myapp") == false)
        }

        @Test("isRegistered returns true when knownSchemes populated")
        func isRegisteredTrue() {
            KSAndroidDeepLinkBackend.knownSchemes = ["myapp"]
            let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
            let result = backend.isRegistered(scheme: "myapp")
            // 재설정
            KSAndroidDeepLinkBackend.knownSchemes = []
            #expect(result == true)
        }
    }
#endif
