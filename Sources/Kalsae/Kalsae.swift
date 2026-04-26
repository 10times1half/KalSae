@_exported public import KalsaeCore
@_exported public import KalsaeMacros

#if os(macOS)
internal import KalsaePlatformMac
#elseif os(Windows)
internal import KalsaePlatformWindows
#elseif os(Linux)
internal import KalsaePlatformLinux
#endif

/// Top-level entry point: returns the platform backend compiled for the
/// current OS. Returns `nil` on unsupported platforms.
public enum Kalsae {
    /// Semantic version of the framework.
    public static let version = "0.0.4-phase4"

    /// Creates the platform backend for the current OS.
    public static func makePlatform() throws(KSError) -> any KSPlatform {
        #if os(macOS)
        return KSMacPlatform()
        #elseif os(Windows)
        return KSWindowsPlatform()
        #elseif os(Linux)
        return KSLinuxPlatform()
        #else
        throw KSError.unsupportedPlatform(
            "Only macOS, Windows and Linux are supported")
        #endif
    }
}
