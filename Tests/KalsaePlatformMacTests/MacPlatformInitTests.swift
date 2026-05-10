#if os(macOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformMac
    import KalsaeCore

    // MARK: - KSMacPlatform 초기화 검증
    //
    // 플랫폼 이니셜라이저가 올바른 백엔드 타입을 배선하고
    // commandRegistry를 공유하는지 확인한다.

    @Suite("KSMacPlatform — init & backend wiring")
    struct KSMacPlatformInitTests {

        /// 각 `var` 프로퍼티가 올바른 구체 타입을 반환해야 한다.
        @Test("All PAL backend properties return correct concrete types")
        func backendTypesAreCorrect() {
            let platform = KSMacPlatform()
            #expect(platform.windows is KSMacWindowBackend)
            #expect(platform.dialogs is KSMacDialogBackend)
            #expect((platform.tray as? KSMacTrayBackend) != nil)
            #expect(platform.menus is KSMacMenuBackend)
            #expect(platform.notifications is KSMacNotificationBackend)
            #expect((platform.shell as? KSMacShellBackend) != nil)
            #expect((platform.clipboard as? KSMacClipboardBackend) != nil)
        }

        /// `commandRegistry`에 커맨드를 등록한 뒤 같은 레지스트리로
        /// dispatch해 반환값이 일치함을 확인 — 레지스트리가 올바로
        /// 배선됐다는 행위적 증거.
        @Test("commandRegistry wiring — register and dispatch round-trip")
        func commandRegistryRoundTrip() async {
            let platform = KSMacPlatform()
            let registry = platform.commandRegistry
            await registry.register("ks.test.echo") { data in .success(data) }

            let payload = Data("hello-macos".utf8)
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
