internal import KalsaeCore

#if os(macOS)
internal import KalsaePlatformMac
#elseif os(Windows)
internal import KalsaePlatformWindows
#elseif os(Linux)
internal import KalsaePlatformLinux
#endif

/// Type-safe wrapper carrying exactly one concrete platform host.
///
/// Implemented as a `#if`-conditioned enum so that the active platform's
/// case is the only inhabitant on a given build, letting the compiler
/// prove exhaustiveness without any optional/force-unwrap.
@MainActor
internal enum AnyPlatformHost {
    #if os(Windows)
    case windows(KSWindowsDemoHost)
    #elseif os(macOS)
    case mac(KSMacDemoHost)
    #elseif os(Linux)
    case linux(KSLinuxDemoHost)
    #endif
}
