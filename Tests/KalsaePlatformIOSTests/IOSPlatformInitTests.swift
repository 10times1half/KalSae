#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSPlatform 초기화 검증

    @Suite("KSiOSPlatform — init & backend wiring")
    struct KSiOSPlatformInitTests {

        @Test("All PAL backend properties return correct concrete types")
        func backendTypesAreCorrect() {
            let platform = KSiOSPlatform()
            #expect(platform.windows is KSiOSWindowBackend)
            #expect(platform.dialogs is KSiOSDialogBackend)
            #expect(platform.tray == nil)
            #expect(platform.menus is KSiOSMenuBackend)
            #expect(platform.notifications is KSiOSNotificationBackend)
            #expect((platform.shell as? KSiOSShellBackend) != nil)
            #expect((platform.clipboard as? KSiOSClipboardBackend) != nil)
            #expect(platform.accelerators == nil)
            #expect((platform.autostart as? KSiOSAutostartBackend) != nil)
            #expect((platform.deepLink as? KSiOSDeepLinkBackend) != nil)
        }

        @Test("commandRegistry wiring — register and dispatch round-trip")
        func commandRegistryRoundTrip() async {
            let platform = KSiOSPlatform()
            let registry = platform.commandRegistry
            await registry.register("ks.test.echo") { data in .success(data) }

            let payload = Data("hello-ios".utf8)
            let result = await registry.dispatch(name: "ks.test.echo", args: payload)
            switch result {
            case .success(let d):
                #expect(d == payload)
            case .failure(let e):
                Issue.record("Echo command must succeed: \(e)")
            }
        }
    }
#endif
