#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSDialogBackend 계약 (Phase iOS-Stable §1.1: 기본 UIKit 핸들러 자동 설치)

    @Suite("KSiOSDialogBackend — defaults install + custom override")
    struct KSiOSDialogBackendTests {

        @Test("init installs default UIKit handlers (openFile/saveFile/selectFolder/message)")
        func defaultsInstalledOnInit() {
            let backend = KSiOSDialogBackend()
            #expect(backend.onOpenFile != nil)
            #expect(backend.onSaveFile != nil)
            #expect(backend.onSelectFolder != nil)
            #expect(backend.onMessage != nil)
        }

        @Test("openFile honours injected override")
        func openFileSucceedsWithHandler() async {
            let backend = KSiOSDialogBackend()
            backend.onOpenFile = { _, _ in [URL(fileURLWithPath: "/tmp/test.txt")] }
            let options = KSOpenFileOptions()
            do {
                let urls = try await backend.openFile(options: options, parent: nil)
                #expect(urls.count == 1)
                #expect(urls.first?.lastPathComponent == "test.txt")
            } catch let e {
                Issue.record("Should not throw: \(e)")
            }
        }

        @Test("message honours injected override")
        func messageSucceedsWithHandler() async {
            let backend = KSiOSDialogBackend()
            backend.onMessage = { _, _ in 0 }
            let options = KSMessageOptions(message: "hello")
            do {
                let result = try await backend.message(options, parent: nil)
                #expect(result == 0)
            } catch let e {
                Issue.record("Should not throw: \(e)")
            }
        }
    }
#endif
