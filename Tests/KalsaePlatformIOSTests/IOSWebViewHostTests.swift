#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSWebViewHost 계약

    @Suite("KSiOSWebViewHost — unit contract", .serialized)
    @MainActor
    struct KSiOSWebViewHostTests {

        @Test("init creates WKWebView")
        func initCreatesWebView() {
            let host = KSiOSWebViewHost(label: "ks-test-ios-wvh")
            #expect(host.webView.frame == .zero)
        }

        @Test("addDocumentCreatedScript does not throw")
        func addDocumentCreatedScriptNoThrow() {
            let host = KSiOSWebViewHost(label: "ks-test-ios-wvh-script")
            do {
                try host.addDocumentCreatedScript("console.log('hello');")
            } catch let e {
                Issue.record("addDocumentCreatedScript threw: \(e)")
            }
        }

        @Test("setAssetRoot with nonexistent path does not throw")
        func setAssetRootNoThrow() {
            let host = KSiOSWebViewHost(label: "ks-test-ios-wvh-root")
            let root = URL(fileURLWithPath: "/tmp/ks-ios-test-root")
            do {
                try host.setAssetRoot(root)
            } catch let e {
                Issue.record("setAssetRoot threw: \(e)")
            }
        }

        @Test("setContentSecurityPolicy does not throw")
        func setContentSecurityPolicyNoThrow() async {
            let host = KSiOSWebViewHost(label: "ks-test-ios-wvh-csp")
            do {
                try await host.setContentSecurityPolicy("default-src 'self'")
            } catch let e {
                Issue.record("setContentSecurityPolicy threw: \(e)")
            }
        }

        @Test("navigate with invalid URL throws webviewInitFailed")
        func navigateInvalidURLThrows() {
            let host = KSiOSWebViewHost(label: "ks-test-ios-wvh-nav")
            do {
                try host.navigate(url: "not a url !!!")
                Issue.record("Expected webviewInitFailed")
            } catch let e {
                #expect(e.code == .webviewInitFailed)
            }
        }
    }
#endif
