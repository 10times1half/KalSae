@_exported public import KalsaeCore
@_exported public import KalsaeMacros

#if os(macOS)
internal import KalsaePlatformMac
#elseif os(iOS)
internal import KalsaePlatformIOS
#elseif os(Android)
internal import KalsaePlatformAndroid
#elseif os(Windows)
internal import KalsaePlatformWindows
#elseif os(Linux)
internal import KalsaePlatformLinux
#endif

/// 최상위 진입점: 현재 OS용으로 컴파일된 플랫폼 백엔드를 반환한다.
/// 지원되지 않는 플랫폼에서는 오류를 던진다.
public enum Kalsae {
    /// 프레임워크의 시맨틱 버전.
    public static let version = "0.0.4-phase4"

    /// 현재 OS용 플랫폼 백엔드를 생성한다.
    public static func makePlatform() throws(KSError) -> any KSPlatform {
        #if os(macOS)
        return KSMacPlatform()
        #elseif os(iOS)
        return KSiOSPlatform()
        #elseif os(Android)
        return KSAndroidPlatform()
        #elseif os(Windows)
        return KSWindowsPlatform()
        #elseif os(Linux)
        return KSLinuxPlatform()
        #else
        throw KSError.unsupportedPlatform(
            "Only iOS, Android, macOS, Windows and Linux are supported")
        #endif
    }
}
