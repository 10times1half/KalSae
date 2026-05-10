#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSShellBackend 계약 (openExternal)

    @Suite("KSiOSShellBackend — unit contract")
    struct KSiOSShellBackendTests {

        let backend = KSiOSShellBackend()

        @Test("showItemInFolder throws unsupportedPlatform")
        func showItemInFolderThrows() async {
            do {
                try await backend.showItemInFolder(URL(fileURLWithPath: "/tmp"))
                Issue.record("Expected unsupportedPlatform to be thrown")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("moveToTrash throws unsupportedPlatform")
        func moveToTrashThrows() async {
            do {
                try await backend.moveToTrash(URL(fileURLWithPath: "/tmp/test.txt"))
                Issue.record("Expected unsupportedPlatform to be thrown")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }
    }
#endif
