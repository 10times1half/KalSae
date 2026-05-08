/// 컴파일 시점의 빌드 모드 식별. `KSWebViewPreferences.developerExtrasEnabled`
/// 등 옵셔널 토글의 기본값을 결정하는 데 사용된다.
public enum KSBuildMode {
    /// `true`이면 디버그 빌드 (Swift `-Onone` / `DEBUG` 플래그).
    /// SwiftPM의 `-c debug` 빌드에서 자동으로 활성화된다.
    public static let isDebug: Bool = {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }()
}
