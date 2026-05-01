#if os(Linux)
import Testing
import Foundation
@testable import KalsaePlatformLinux
import KalsaeCore

@Suite("KSLinuxDialogBackend — wiring contract")
struct KSLinuxDialogIntegrationTests {

    @Test("platform exposes Linux dialog backend")
    func platformExposesDialogBackend() {
        let platform = KSLinuxPlatform()
        #expect(platform.dialogs is KSLinuxDialogBackend)
    }

    @Test("dialog backend API surface is callable from async context")
    func dialogApiSurfaceCallable() {
        let backend = KSLinuxDialogBackend()

        let openRef: (KSOpenFileOptions, KSWindowHandle?) async throws(KSError) -> [URL] =
            backend.openFile
        let saveRef: (KSSaveFileOptions, KSWindowHandle?) async throws(KSError) -> URL? =
            backend.saveFile
        let folderRef: (KSSelectFolderOptions, KSWindowHandle?) async throws(KSError) -> URL? =
            backend.selectFolder
        let messageRef: (KSMessageOptions, KSWindowHandle?) async throws(KSError) -> KSMessageResult =
            backend.message

        _ = openRef
        _ = saveRef
        _ = folderRef
        _ = messageRef
        #expect(true)
    }
}
#endif
