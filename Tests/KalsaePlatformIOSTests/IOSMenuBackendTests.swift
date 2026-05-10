#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSMenuBackend 계약 (throws unsupportedPlatform)

    @Suite("KSiOSMenuBackend — throws unsupportedPlatform")
    struct KSiOSMenuBackendTests {

        let backend = KSiOSMenuBackend()

        @Test("installAppMenu throws unsupportedPlatform")
        func installAppMenuThrows() async {
            do {
                try await backend.installAppMenu([])
                Issue.record("installAppMenu should throw on iOS")
            } catch let e {
                #expect(
                    e.code == .unsupportedPlatform,
                    "Expected unsupportedPlatform, got \(e.code)")
            }
        }

        @Test("showContextMenu throws unsupportedPlatform")
        func showContextMenuThrows() async {
            let handle = KSWindowHandle(label: "ks-test-ios-menu", rawValue: 1)
            do {
                try await backend.showContextMenu([], at: KSPoint(x: 0, y: 0), in: handle)
                Issue.record("showContextMenu should throw on iOS")
            } catch let e {
                #expect(
                    e.code == .unsupportedPlatform,
                    "Expected unsupportedPlatform, got \(e.code)")
            }
        }
    }
#endif
