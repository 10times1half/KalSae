internal import Foundation
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

/// 플랫폼별 DemoHost 인스턴스를 생성하는 팩토리.
/// 조건부 컴파일을 1곳으로 집중시켜 신규 플랫폼 추가 시
/// 수정 범위를 최소화한다.
internal enum KSDemoHostFactory {
    /// 지정된 윈도우 설정과 명령 레지스트리로 플랫폼 호스트를 생성한다.
    /// 각 플랫폼 DemoHost의 init 로직은 그대로 유지한다.
    @MainActor
    static func makeHost(
        windowConfig: KSWindowConfig,
        registry: KSCommandRegistry,
        restoredState: KSPersistedWindowState? = nil
    ) throws(KSError) -> any KSDemoHost {
        #if os(Windows)
            return try KSWindowsDemoHost(
                windowConfig: windowConfig,
                registry: registry,
                restoredState: restoredState)
        #elseif os(macOS)
            return try KSMacDemoHost(
                windowConfig: windowConfig,
                registry: registry)
        #elseif os(Linux)
            return try KSLinuxDemoHost(
                windowConfig: windowConfig,
                registry: registry)
        #elseif os(iOS)
            return try KSiOSDemoHost(
                windowConfig: windowConfig,
                registry: registry)
        #elseif os(Android)
            return try KSAndroidDemoHost(
                windowConfig: windowConfig,
                registry: registry)
        #else
            #error("Unsupported platform")
        #endif
    }
}
