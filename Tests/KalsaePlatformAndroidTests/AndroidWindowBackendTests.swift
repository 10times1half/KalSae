#if os(Android)
    import Testing
    import Foundation
    @testable import KalsaePlatformAndroid
    import KalsaeCore

    // MARK: - KSAndroidWindowBackend 유닛 계약

    @Suite("KSAndroidWindowBackend — unit contract")
    struct KSAndroidWindowBackendUnitTests {

        let backend = KSAndroidWindowBackend()

        @Test("webView(for:) throws webviewInitFailed for unknown handle")
        func webViewForMissingHandle() async {
            let handle = KSWindowHandle(label: "ks-test-android-ghost-wv", rawValue: 0)
            do {
                _ = try await backend.webView(for: handle)
                Issue.record("Expected webviewInitFailed to be thrown")
            } catch let e {
                #expect(
                    e.code == .webviewInitFailed,
                    "Expected webviewInitFailed, got \(e.code)")
            }
        }

        @Test("show() throws windowCreationFailed for unknown handle")
        func showMissingHandle() async {
            let handle = KSWindowHandle(label: "ks-test-android-ghost-show", rawValue: 0)
            do {
                try await backend.show(handle)
                Issue.record("Expected windowCreationFailed to be thrown")
            } catch let e {
                #expect(
                    e.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(e.code)")
            }
        }

        @Test("find(label:) returns nil for unknown label")
        func findUnknownLabel() async {
            let result = await backend.find(
                label: "ks-test-android-nonexistent-\(UInt64.random(in: 1...UInt64.max))")
            #expect(result == nil)
        }

        @Test("create() — handle is findable by label")
        func createThenFind() async {
            let config = KSWindowConfig(
                label: "ks-test-android-be-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS Android Test",
                width: 360, height: 800, visible: true)

            do {
                let handle = try await backend.create(config)
                defer { Task { try? await backend.close(handle) } }
                let found = await backend.find(label: config.label)
                #expect(found?.label == config.label)
            } catch let e {
                Issue.record("create() failed unexpectedly: \(e)")
            }
        }

        @Test("create() — handle appears in all()")
        func createAppearsInAll() async {
            let config = KSWindowConfig(
                label: "ks-test-android-all-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS Android All Test",
                width: 360, height: 800, visible: true)

            do {
                let handle = try await backend.create(config)
                defer { Task { try? await backend.close(handle) } }
                let all = await backend.all()
                #expect(all.contains { $0.label == config.label })
            } catch let e {
                Issue.record("create() failed unexpectedly: \(e)")
            }
        }

        @Test("close() — handle is no longer findable")
        func closeRemovesFromRegistry() async {
            let config = KSWindowConfig(
                label: "ks-test-android-close-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS Android Close Test",
                width: 360, height: 800, visible: true)

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
