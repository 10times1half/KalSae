#if os(macOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformMac

    @Suite("WKWebViewHost — unit contract", .serialized)
    @MainActor
    struct WKWebViewHostTests {

        @Test("setContentSecurityPolicy does not throw")
        func setContentSecurityPolicyNoThrow() async {
            let host = WKWebViewHost(label: "ks-test-mac-wvh-csp")
            do {
                try await host.setContentSecurityPolicy("default-src 'self'")
            } catch let e {
                Issue.record("setContentSecurityPolicy threw: \(e)")
            }
        }
    }
#endif
