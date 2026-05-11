#if os(macOS)
    import Foundation

    /// macOS 앱이 sandbox 컨테이너 (MAS / TestFlight / 일반 sandbox 빌드)에서
    /// 실행 중인지 감지한다. PAL 백엔드가 비호환 API 를 no-op 으로 분기하는
    /// 데 사용한다 (RFC-008 P3).
    ///
    /// 검출 우선순위:
    ///   1. `KALSAE_MAS_CONTEXT=1` 환경변수 (단위 테스트 / 강제 분기용)
    ///   2. `APP_SANDBOX_CONTAINER_ID` 환경변수 (macOS sandbox 가 자동 주입)
    ///
    /// 두 값 모두 없으면 `false`. App Store 심사 통과한 빌드는 자동으로
    /// `APP_SANDBOX_CONTAINER_ID` 가 설정되므로 false-positive 위험이 없다.
    public enum KSMacAppPackageContext {
        public static func isSandboxed() -> Bool {
            let env = ProcessInfo.processInfo.environment
            if let v = env["KALSAE_MAS_CONTEXT"], v == "1" || v.lowercased() == "true" {
                return true
            }
            if env["APP_SANDBOX_CONTAINER_ID"] != nil {
                return true
            }
            return false
        }
    }
#endif
