internal import KalsaeCore

#if os(macOS)
internal import KalsaePlatformMac
#elseif os(Windows)
internal import KalsaePlatformWindows
#elseif os(Linux)
internal import KalsaePlatformLinux
#elseif os(iOS)
internal import KalsaePlatformIOS
#elseif os(Android)
internal import KalsaePlatformAndroid
#endif

/// 정확히 하나의 구체적인 플랫폼 호스트를 담는 타입 안전 래퍼.
///
/// `#if` 조건부 열거형으로 구현되어, 활성 플랫폼의 case만이 해당 빌드에
/// 존재하게 되어 컴파일러가 옵셔널/강제 언래핑 없이 완전함을 증명할 수 있다.
@MainActor
internal enum AnyPlatformHost {
    #if os(Windows)
    case windows(KSWindowsDemoHost)
    #elseif os(macOS)
    case mac(KSMacDemoHost)
    #elseif os(Linux)
    case linux(KSLinuxDemoHost)
    #elseif os(iOS)
    case ios(KSiOSDemoHost)
    #elseif os(Android)
    case android(KSAndroidDemoHost)
    #endif
}
