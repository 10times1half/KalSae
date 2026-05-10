#if os(macOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformMac
    import KalsaeCore

    // MARK: - KSMacWindowBackend.webView(for:) + close() 계약 테스트

    @Suite("KSMacWindowBackend — webView(for:) contract", .serialized)
    @MainActor
    struct KSMacWindowBackendWebViewTests {

        private func makeConfig() -> KSWindowConfig {
            KSWindowConfig(
                label: "ks-test-mac-wv-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS Mac WebView Test",
                width: 400,
                height: 300,
                visible: false
            )
        }

        private func setUp() {
            KSMacApp.shared.ensureInitialized()
        }

        /// `close()` 후 `webView(for:)`는 `windowCreationFailed`를 던져야 한다.
        @Test("webView(for:) throws windowCreationFailed after close()")
        func webViewThrowsAfterClose() async {
            setUp()
            let backend = KSMacWindowBackend()
            let config = makeConfig()

            do {
                let handle = try await backend.create(config)
                try await backend.close(handle)

                do {
                    _ = try await backend.webView(for: handle)
                    Issue.record("Expected windowCreationFailed after close()")
                } catch let e {
                    #expect(
                        e.code == .windowCreationFailed,
                        "Got \(e.code), expected windowCreationFailed")
                }
            } catch let e {
                Issue.record("create() failed unexpectedly: \(e)")
            }
        }

        /// `close()` 후 `find(label:)`은 `nil`을 반환해야 한다.
        @Test("find(label:) returns nil after close()")
        func findNilAfterClose() async {
            setUp()
            let backend = KSMacWindowBackend()
            let config = makeConfig()

            do {
                let handle = try await backend.create(config)
                try await backend.close(handle)
                let found = await backend.find(label: config.label)
                #expect(found == nil)
            } catch let e {
                Issue.record("Unexpected error: \(e)")
            }
        }
    }
#endif
