#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSDialogBackend 계약 (핸들러 주입형 — bridge 없이 throw)

    @Suite("KSiOSDialogBackend — throws when bridge not installed")
    struct KSiOSDialogBackendTests {

        let backend = KSiOSDialogBackend()

        @Test("openFile throws unsupportedPlatform when bridge absent")
        func openFileThrowsWhenNoBridge() async {
            let options = KSOpenFileOptions()
            do {
                _ = try await backend.openFile(options: options, parent: nil)
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("message throws unsupportedPlatform when bridge absent")
        func messageThrowsWhenNoBridge() async {
            let options = KSMessageOptions(message: "test")
            do {
                _ = try await backend.message(options, parent: nil)
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("openFile succeeds when handler is installed")
        func openFileSucceedsWithHandler() async {
            let backend2 = KSiOSDialogBackend()
            backend2.onOpenFile = { _, _ in [URL(fileURLWithPath: "/tmp/test.txt")] }
            let options = KSOpenFileOptions()
            do {
                let urls = try await backend2.openFile(options: options, parent: nil)
                #expect(urls.count == 1)
            } catch let e {
                Issue.record("Should not throw: \(e)")
            }
        }
    }
#endif
