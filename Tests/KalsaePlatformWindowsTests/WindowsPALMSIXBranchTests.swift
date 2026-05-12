#if os(Windows)
    import Testing
    import Foundation
    @testable import KalsaePlatformWindows
    import KalsaeCore

    /// MSIX 컨텍스트 감지 + Autostart/DeepLink no-op 분기 검증 (RFC-008 P2).
    ///
    /// `KALSAE_MSIX_CONTEXT=1` 환경변수로 toggle 가능. 단위 테스트는 환경변수를
    /// 직접 set/unset 해서 양 분기를 모두 커버한다. 환경변수는 프로세스
    /// 전역이므로 suite 안의 테스트들은 직렬화해 서로의 toggle 이 leak 되지
    /// 않도록 한다.
    @Suite("RFC-008 P2 — Windows PAL MSIX branches", .serialized)
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

        /// `putenv("KEY=")` 는 변수를 unset 하는 대신 빈 문자열로 남겨두는
        /// 플랫폼이 있다. `isMSIXPackaged()` 가 toggle 검사 시 빈 문자열을
        /// truthy 로 잘못 해석하지 않고 Win32 API fallback 으로 떨어져
        /// false 를 반환해야 한다.
        @Test("isMSIXPackaged ignores empty-string KALSAE_MSIX_CONTEXT and falls back to Win32 API")
        func envEmptyStringIgnored() {
            setMSIXEnv("")
            defer { setMSIXEnv(nil) }
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
