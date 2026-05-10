#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSWindowBackend 유닛 계약

    @Suite("KSiOSWindowBackend — unit contract")
    struct KSiOSWindowBackendUnitTests {

        let backend = KSiOSWindowBackend()

        /// 존재하지 않는 핸들로 `webView(for:)`를 호출하면
        /// `webviewInitFailed` 에러가 나와야 한다.
        @Test("webView(for:) throws webviewInitFailed for unknown handle")
        func webViewForMissingHandle() async {
            let handle = KSWindowHandle(label: "ks-test-ios-ghost-wv", rawValue: 0)
            do {
                _ = try await backend.webView(for: handle)
                Issue.record("Expected webviewInitFailed to be thrown")
            } catch let e {
                #expect(
                    e.code == .webviewInitFailed,
                    "Expected webviewInitFailed, got \(e.code)")
            }
        }

        /// 존재하지 않는 핸들로 `show()`를 호출하면
        /// `windowCreationFailed` 에러가 나와야 한다.
        @Test("show() throws windowCreationFailed for unknown handle")
        func showMissingHandle() async {
            let handle = KSWindowHandle(label: "ks-test-ios-ghost-show", rawValue: 0)
            do {
                try await backend.show(handle)
                Issue.record("Expected windowCreationFailed to be thrown")
            } catch let e {
                #expect(
                    e.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(e.code)")
            }
        }

        /// `find(label:)`은 존재하지 않는 레이블에 대해 `nil`을 반환해야 한다.
        @Test("find(label:) returns nil for unknown label")
        func findUnknownLabel() async {
            let result = await backend.find(
                label: "ks-test-ios-nonexistent-\(UInt64.random(in: 1...UInt64.max))")
            #expect(result == nil)
        }

        /// `create()` 후 `find(label:)`이 핸들을 반환해야 한다.
        @Test("create() — handle is findable by label")
        func createThenFind() async {
            let config = KSWindowConfig(
                label: "ks-test-ios-be-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS iOS Test",
                width: 390, height: 844, visible: true)

            do {
                let handle = try await backend.create(config)
                defer { Task { try? await backend.close(handle) } }
                let found = await backend.find(label: config.label)
                #expect(found?.label == config.label)
            } catch let e {
                Issue.record("create() failed unexpectedly: \(e)")
            }
        }

        /// `create()` 후 `all()`이 해당 핸들을 포함해야 한다.
        @Test("create() — handle appears in all()")
        func createAppearsInAll() async {
            let config = KSWindowConfig(
                label: "ks-test-ios-all-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS iOS All Test",
                width: 390, height: 844, visible: true)

            do {
                let handle = try await backend.create(config)
                defer { Task { try? await backend.close(handle) } }
                let all = await backend.all()
                #expect(all.contains { $0.label == config.label })
            } catch let e {
                Issue.record("create() failed unexpectedly: \(e)")
            }
        }

        /// `close()` 후 `find(label:)`이 `nil`을 반환해야 한다.
        @Test("close() — handle is no longer findable")
        func closeRemovesFromRegistry() async {
            let config = KSWindowConfig(
                label: "ks-test-ios-close-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS iOS Close Test",
                width: 390, height: 844, visible: true)

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
