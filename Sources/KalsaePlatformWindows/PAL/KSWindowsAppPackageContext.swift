#if os(Windows)
    internal import WinSDK
    internal import Foundation

    /// MSIX 패키지 컨텍스트에서 실행 중인지 감지한다 (RFC-008 P2).
    ///
    /// 검사 순서:
    ///   1. `KALSAE_MSIX_CONTEXT=1` 환경변수 (개발 / 테스트 강제 toggle).
    ///   2. Win32 `GetCurrentPackageFullName(length=0, nil)` 의 반환 코드를
    ///      화이트리스트 매칭한다:
    ///        * `ERROR_SUCCESS(0)` 또는 `ERROR_INSUFFICIENT_BUFFER(122)`
    ///          → packaged (true)
    ///        * `APPMODEL_ERROR_NO_PACKAGE(15700)` 포함한 그 외 모든 rc
    ///          → 안전 측 default unpackaged (false)
    ///
    /// 알 수 없는 rc(API 미존재 환경, 권한 오류 등) 도 false 로 처리해
    /// 비-MSIX 환경에서 Autostart/DeepLink 백엔드가 Registry 쓰기를 silent
    /// 하게 스킵하는 회귀를 막는다.
    ///
    /// MSIX 안에서는 Autostart Registry 쓰기 / DeepLink Registry 쓰기가
    /// **AppxManifest 의 `windows.startupTask` / `windows.protocol` 선언**으로
    /// 대체되므로 PAL 백엔드는 no-op + 경고 로그를 남기고 success 를 반환한다.
    public enum KSWindowsAppPackageContext {

        public static func isMSIXPackaged() -> Bool {
            // 1) 명시적 toggle (CI / 단위 테스트).
            if let raw = ProcessInfo.processInfo.environment["KALSAE_MSIX_CONTEXT"],
                raw == "1" || raw.lowercased() == "true"
            {
                return true
            }
            // 2) Win32 API. UINT32 length=0 으로 호출하면 packaged 프로세스는
            //    ERROR_INSUFFICIENT_BUFFER(122) 를 반환하고, unpackaged 프로세스는
            //    APPMODEL_ERROR_NO_PACKAGE(15700) 를 반환한다. 그 외 rc(API 미존재
            //    환경, 권한 오류 등)는 안전 측 default(false)로 처리해, 비-MSIX
            //    환경에서 Autostart/DeepLink 백엔드가 Registry 쓰기를 silent 하게
            //    스킵하는 회귀를 막는다.
            var length: UINT32 = 0
            let rc = GetCurrentPackageFullName(&length, nil)
            // ERROR_SUCCESS(0) 또는 ERROR_INSUFFICIENT_BUFFER(122) 만 packaged 로 인정.
            return rc == 0 || rc == 122
        }
    }
#endif
