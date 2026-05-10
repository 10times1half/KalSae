#if os(Android)
    import Testing
    import Foundation
    @testable import KalsaePlatformAndroid
    import KalsaeCore

    // MARK: - KSAndroidPlatform 초기화 검증

    @Suite("KSAndroidPlatform — init & backend wiring")
    struct KSAndroidPlatformInitTests {

        @Test("All PAL backend properties return correct concrete types")
        func backendTypesAreCorrect() {
            let platform = KSAndroidPlatform()
            #expect(platform.windows is KSAndroidWindowBackend)
            #expect(platform.dialogs is KSAndroidDialogBackend)
            #expect(platform.tray == nil)
            #expect(platform.menus is KSAndroidMenuBackend)
            #expect(platform.notifications is KSAndroidNotificationBackend)
            #expect((platform.shell as? KSAndroidShellBackend) != nil)
            #expect((platform.clipboard as? KSAndroidClipboardBackend) != nil)
            #expect(platform.accelerators == nil)
            #expect((platform.autostart as? KSAndroidAutostartBackend) != nil)
            #expect((platform.deepLink as? KSAndroidDeepLinkBackend) != nil)
        }

        @Test("commandRegistry wiring — register and dispatch round-trip")
        func commandRegistryRoundTrip() async {
            let platform = KSAndroidPlatform()
            let registry = platform.commandRegistry
            await registry.register("ks.test.echo") { data in .success(data) }

            let payload = Data("hello-android".utf8)
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
