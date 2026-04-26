internal import Foundation

#if os(Windows)
internal import KalsaePlatformWindows
#endif

extension KSApp {

    /// Outcome of a single-instance acquisition attempt.
    public enum SingleInstanceOutcome: Sendable {
        /// This process is the primary instance. Continue normal startup.
        case primary
        /// Another instance is already running and arguments were
        /// forwarded to it. Caller should exit immediately.
        case relayed
    }

    /// Ensures only one instance of the application runs at a time.
    ///
    /// On the first launch this process becomes the **primary** and
    /// returns `.primary`. Subsequent launches detect the primary, send
    /// their command-line arguments to it, and return `.relayed` —
    /// callers must exit immediately. The primary receives the relayed
    /// arguments via `onSecondInstance` (invoked on the main thread).
    ///
    /// On platforms without a single-instance backend (currently macOS
    /// and Linux) this is a no-op that always returns `.primary`.
    ///
    /// Call this **before** `boot(...)`:
    /// ```swift
    /// switch await KSApp.singleInstance(identifier: "dev.example.MyApp") { args in
    ///     // focus the existing window, parse `args`, etc.
    /// } {
    /// case .relayed: exit(EXIT_SUCCESS)
    /// case .primary: break
    /// }
    /// let app = try await KSApp.boot(configURL: configURL) { _ in }
    /// ```
    @MainActor
    public static func singleInstance(
        identifier: String,
        args: [String] = CommandLine.arguments,
        onSecondInstance: @escaping @MainActor ([String]) -> Void
    ) -> SingleInstanceOutcome {
        #if os(Windows)
        switch KSWindowsSingleInstance.acquire(
            identifier: identifier,
            args: args,
            onSecondInstance: onSecondInstance)
        {
        case .primary: return .primary
        case .relayed: return .relayed
        }
        #else
        _ = identifier
        _ = args
        _ = onSecondInstance
        return .primary
        #endif
    }
}
