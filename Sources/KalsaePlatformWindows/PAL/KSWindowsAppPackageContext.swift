#if os(Windows)
    internal import WinSDK
    internal import Foundation

    /// MSIX 패키지 컨텍스트에서 실행 중인지 감지한다 (RFC-008 P2).
    ///
    /// 검사 순서:
    ///   1. `KALSAE_MSIX_CONTEXT=1` 환경변수 (개발 / 테스트 강제 toggle).
    ///   2. Win32 `GetCurrentPackageFullName` → `ERROR_SUCCESS` 면 MSIX.
    ///      `APPMODEL_ERROR_NO_PACKAGE(15700)` 면 일반 데스크탑 프로세스.
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
            // 2) Win32 API. UINT32 length=0 → ERROR_INSUFFICIENT_BUFFER 면 packaged,
            //    APPMODEL_ERROR_NO_PACKAGE(15700) 면 unpackaged.
            var length: UINT32 = 0
            let rc = GetCurrentPackageFullName(&length, nil)
            // APPMODEL_ERROR_NO_PACKAGE
            if rc == 15700 { return false }
            // ERROR_INSUFFICIENT_BUFFER(122) 또는 ERROR_SUCCESS(0) → packaged.
            return true
        }
    }
#endif
