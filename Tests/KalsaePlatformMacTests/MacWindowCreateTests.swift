#if os(macOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformMac
    import KalsaeCore

    // MARK: - KSMacWindowBackend.create() 계약 테스트

    @Suite("KSMacWindowBackend — create() contract", .serialized)
    @MainActor
    struct KSMacWindowBackendCreateTests {

        private func makeConfig() -> KSWindowConfig {
            KSWindowConfig(
                label: "ks-test-mac-be-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS Mac Backend Test",
                width: 400,
                height: 300,
                visible: false
            )
        }

        private func setUp() {
            KSMacApp.shared.ensureInitialized()
        }

        /// `create()` 성공 시 핸들의 레이블이 config.label과 일치해야 한다.
        @Test("create() — handle label matches config.label")
        func createHandleLabelMatchesConfig() async {
            setUp()
            let backend = KSMacWindowBackend()
            let config = makeConfig()

            do {
                let handle = try await backend.create(config)
                defer { Task { try? await backend.close(handle) } }
                #expect(handle.label == config.label)
            } catch let e {
                Issue.record("create() failed unexpectedly: \(e)")
            }
        }

        /// `create()` 성공 시 rawValue가 0이 아니어야 한다.
        @Test("create() — rawValue is non-zero")
        func createHandleRawValueNonZero() async {
            setUp()
            let backend = KSMacWindowBackend()
            let config = makeConfig()

            do {
                let handle = try await backend.create(config)
                defer { Task { try? await backend.close(handle) } }
                #expect(handle.rawValue != 0)
            } catch let e {
                Issue.record("create() failed unexpectedly: \(e)")
            }
        }

        /// `create()` 성공 시 `all()`에 해당 창이 포함돼야 한다.
        @Test("create() — window appears in all() after successful init")
        func createAppearsInAll() async {
            setUp()
            let backend = KSMacWindowBackend()
            let config = makeConfig()

            do {
                let handle = try await backend.create(config)
                let all = await backend.all()
                try? await backend.close(handle)
                #expect(all.contains { $0.label == config.label })
            } catch let e {
                Issue.record("create() failed unexpectedly: \(e)")
            }
        }

        /// `create()` 성공 시 `webView(for:)`가 `KSWebViewBackend`를 반환해야 한다.
        @Test("create() — webView(for:) returns KSWebViewBackend")
        func createWebViewReturnsBackend() async {
            setUp()
            let backend = KSMacWindowBackend()
            let config = makeConfig()

            do {
                let handle = try await backend.create(config)
                let webview = try await backend.webView(for: handle)
                try? await backend.close(handle)
                // 반환된 existential은 절대 nil이 아니다.
                _ = webview
            } catch let e {
                Issue.record("create() or webView(for:) failed unexpectedly: \(e)")
            }
        }
    }
#endif
