#if os(Android)
    import Testing
    import Foundation
    @testable import KalsaePlatformAndroid
    import KalsaeCore

    // MARK: - Unsupported backends: error code 확인

    @Suite("KSAndroidPlatform — unsupported backend error codes")
    struct KSAndroidUnsupportedTests {

        @Test("KSAndroidDialogBackend.openFile throws unsupportedPlatform")
        func dialogOpenFileThrows() async {
            let backend = KSAndroidDialogBackend()
            do {
                _ = try await backend.openFile(options: KSOpenFileOptions(), parent: nil)
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("KSAndroidMenuBackend.installAppMenu succeeds silently (no-op)")
        func menuInstallAppMenuNoThrow() async {
            let backend = KSAndroidMenuBackend()
            do {
                try await backend.installAppMenu([])
                // iOS와 동일하게 no-op이어야 한다 — throw 없음.
            } catch let e {
                Issue.record("installAppMenu should not throw on Android: \(e)")
            }
        }

        @Test("KSAndroidShellBackend.openExternal throws when bridge absent")
        func shellOpenExternalThrowsNoBridge() async {
            let backend = KSAndroidShellBackend()
            do {
                try await backend.openExternal(URL(string: "https://example.com")!)
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("KSAndroidShellBackend.moveToTrash throws unsupportedPlatform")
        func shellMoveToTrashThrows() async {
            let backend = KSAndroidShellBackend()
            do {
                try await backend.moveToTrash(URL(string: "file:///tmp/foo")!)
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }
    }
#endif
