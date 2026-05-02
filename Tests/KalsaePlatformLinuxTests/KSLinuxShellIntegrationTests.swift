#if os(Linux)
    import Testing
    import Foundation
    @testable import KalsaePlatformLinux
    import KalsaeCore

    @Suite("KSLinuxShellBackend — integration contract")
    struct KSLinuxShellIntegrationTests {

        @Test("moveToTrash maps process failure to io for missing path")
        func moveToTrashMissingPathThrowsIO() async {
            let backend = KSLinuxShellBackend()
            let missing = URL(fileURLWithPath: "/tmp/ks-missing-\(UUID().uuidString)")

            do {
                try await backend.moveToTrash(missing)
                Issue.record("Expected io error for missing path")
            } catch let error {
                #expect(
                    error.code == .io,
                    "Expected io, got \(error.code)")
            }
        }

        @Test("openExternal either succeeds or throws io")
        func openExternalErrorMapping() async {
            let backend = KSLinuxShellBackend()
            let url = URL(string: "ks-invalid-scheme://\(UUID().uuidString)")!

            do {
                try await backend.openExternal(url)
                // 환경 의존: 콌스텀 핸들러가 있으면 성공할 수 있다.
            } catch let error {
                #expect(
                    error.code == .io,
                    "Expected io on failure, got \(error.code)")
            }
        }

        @Test("showItemInFolder either succeeds or throws io")
        func showItemInFolderErrorMapping() async {
            let backend = KSLinuxShellBackend()
            let missing = URL(fileURLWithPath: "/tmp/ks-show-missing-\(UUID().uuidString)")

            do {
                try await backend.showItemInFolder(missing)
                // 환경 의존: 데스크탑 핸들러가 디렉터리 뷰를 여는 경우도 있다.
            } catch let error {
                #expect(
                    error.code == .io,
                    "Expected io on failure, got \(error.code)")
            }
        }
    }
#endif
