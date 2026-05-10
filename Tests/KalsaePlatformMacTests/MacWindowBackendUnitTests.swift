#if os(macOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformMac
    import KalsaeCore

    // MARK: - KSMacWindowBackend 유닛 계약
    //
    // 잘못된 핸들 / 빈 레지스트리 상태에 대한 에러 코드를 검증한다.

    @Suite("KSMacWindowBackend — unit contract (no NSWindow)")
    struct KSMacWindowBackendUnitTests {

        let backend = KSMacWindowBackend()

        /// 존재하지 않는 핸들로 `webView(for:)`를 호출하면
        /// `windowCreationFailed` 에러가 나와야 한다.
        @Test("webView(for:) throws windowCreationFailed for unknown handle")
        func webViewForMissingHandle() async {
            let handle = KSWindowHandle(label: "ks-test-mac-ghost-wv", rawValue: 0)
            do {
                _ = try await backend.webView(for: handle)
                Issue.record("Expected windowCreationFailed to be thrown")
            } catch let e {
                #expect(
                    e.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(e.code)")
            }
        }

        /// 존재하지 않는 핸들로 `show()`를 호출하면
        /// `windowCreationFailed` 에러가 나와야 한다.
        @Test("show() throws windowCreationFailed for unknown handle")
        func showMissingHandle() async {
            let handle = KSWindowHandle(label: "ks-test-mac-ghost-show", rawValue: 0)
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
                label: "ks-test-mac-nonexistent-\(UInt64.random(in: 1...UInt64.max))")
            #expect(result == nil)
        }
    }
#endif
