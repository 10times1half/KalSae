#if os(Windows)
    import Testing
    import Foundation
    @testable import KalsaePlatformWindows
    import KalsaeCore

    /// MSIX 컨텍스트 감지 + Autostart/DeepLink no-op 분기 검증 (RFC-008 P2).
    ///
    /// `KALSAE_MSIX_CONTEXT=1` 환경변수로 toggle 가능. 단위 테스트는 환경변수를
    /// 직접 set/unset 해서 양 분기를 모두 커버한다.
    @Suite("RFC-008 P2 — Windows PAL MSIX branches")
    struct WindowsPALMSIXBranchTests {

        private static let envVar = "KALSAE_MSIX_CONTEXT"

        private func setMSIXEnv(_ value: String?) {
            if let v = value {
                _ = putenv("\(Self.envVar)=\(v)")
            } else {
                _ = putenv("\(Self.envVar)=")
            }
        }

        @Test("isMSIXPackaged honors KALSAE_MSIX_CONTEXT=1 override")
        func envOverrideOn() {
            setMSIXEnv("1")
            defer { setMSIXEnv(nil) }
            #expect(KSWindowsAppPackageContext.isMSIXPackaged() == true)
        }

        @Test("isMSIXPackaged returns false for unpackaged process when env unset")
        func envOverrideOff() {
            setMSIXEnv(nil)
            #expect(KSWindowsAppPackageContext.isMSIXPackaged() == false)
        }

        @Test("Autostart enable() is a no-op under MSIX (does not throw, does not write registry)")
        func autostartEnableNoOp() throws(KSError) {
            setMSIXEnv("1")
            defer { setMSIXEnv(nil) }
            let backend = KSWindowsAutostartBackend(identifier: "test.kalsae.msix.noop")
            try backend.enable()
            try backend.disable()
            #expect(backend.isEnabled() == false)
        }

        @Test("DeepLink register/unregister are no-ops under MSIX")
        func deepLinkNoOp() throws(KSError) {
            setMSIXEnv("1")
            defer { setMSIXEnv(nil) }
            let backend = KSWindowsDeepLinkBackend(identifier: "test.kalsae.msix.dl")
            try backend.register(scheme: "kalsaemsixtest")
            try backend.unregister(scheme: "kalsaemsixtest")
            #expect(backend.isRegistered(scheme: "kalsaemsixtest") == true)
        }
    }
#endif
