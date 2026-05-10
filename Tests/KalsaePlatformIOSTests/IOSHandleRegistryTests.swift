#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSHandleRegistry 직접 검증

    @Suite("KSiOSHandleRegistry — direct registry contract", .serialized)
    @MainActor
    struct KSiOSHandleRegistryTests {

        @Test("register then handle(for:) returns matching handle")
        func registerThenFind() {
            let label = "ks-test-ios-reg-\(UUID().uuidString.prefix(8).lowercased())"
            let handle = KSiOSHandleRegistry.shared.register(label: label)
            defer { KSiOSHandleRegistry.shared.unregister(handle) }

            let found = KSiOSHandleRegistry.shared.handle(for: label)
            #expect(found != nil)
            #expect(found?.label == label)
        }

        @Test("unregister removes handle from registry")
        func unregisterRemovesHandle() {
            let label = "ks-test-ios-unreg-\(UUID().uuidString.prefix(8).lowercased())"
            let handle = KSiOSHandleRegistry.shared.register(label: label)
            KSiOSHandleRegistry.shared.unregister(handle)
            #expect(KSiOSHandleRegistry.shared.handle(for: label) == nil)
        }

        @Test("webView not registered returns nil")
        func webViewNilBeforeRegister() {
            let label = "ks-test-ios-wv-nil-\(UUID().uuidString.prefix(8).lowercased())"
            #expect(KSiOSHandleRegistry.shared.webView(for: label) == nil)
        }

        @Test("registerWebView then webView(for:) returns host")
        func registerWebViewThenFind() {
            let label = "ks-test-ios-wvreg-\(UUID().uuidString.prefix(8).lowercased())"
            let handle = KSiOSHandleRegistry.shared.register(label: label)
            defer { KSiOSHandleRegistry.shared.unregister(handle) }

            let wvHost = KSiOSWebViewHost(label: label)
            KSiOSHandleRegistry.shared.registerWebView(wvHost, for: label)
            #expect(KSiOSHandleRegistry.shared.webView(for: label) != nil)
        }
    }
#endif
