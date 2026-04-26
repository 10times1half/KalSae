public import Logging
import Foundation

/// Central logging facade for Kalsae.
///
/// Platform backends register their native `LogHandler` via
/// ``bootstrap(factory:)`` (e.g. `os.Logger` on macOS,
/// `OutputDebugStringW` on Windows). Until `bootstrap` is called,
/// `swift-log`'s default stderr handler is used.
public enum KSLog {
    /// Subsystem / reverse-DNS label used by platform log sinks.
    public static let subsystem = "dev.Kalsae"

    /// Call once, early in application startup. Safe to call multiple times
    /// but only the first call has effect (per `swift-log` contract).
    public static func bootstrap(
        _ factory: @Sendable @escaping (String) -> any LogHandler
    ) {
        LoggingSystem.bootstrap(factory)
    }

    /// Convenience logger for a given category.
    public static func logger(_ category: String) -> Logger {
        Logger(label: "\(subsystem).\(category)")
    }
}
