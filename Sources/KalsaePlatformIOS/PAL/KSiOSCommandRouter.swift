#if os(iOS)
    public import KalsaeCore

    /// Routes menu (and future tray) command activations to subscribers on iOS.
    /// Mirrors `KSMacCommandRouter` / `KSWindowsCommandRouter` /
    /// `KSLinuxCommandRouter` / `KSAndroidCommandRouter` so the per-platform
    /// menu backends emit through an identical shape.
    ///
    /// Subscribers are typically wired by `KSApp` so menu activations reach
    /// the same handlers that IPC `__ks.command(...)` calls do.
    @MainActor
    public final class KSiOSCommandRouter: KSMenuCommandRouting {
        public static let shared = KSiOSCommandRouter()

        public typealias Sink = @MainActor (_ command: String, _ itemID: String?) -> Void
        private var sinks: [Sink] = []

        private init() {}

        public func subscribe(_ sink: @escaping Sink) { sinks.append(sink) }
        public func clear() { sinks.removeAll() }

        internal func dispatch(command: String, itemID: String?) {
            for sink in sinks { sink(command, itemID) }
        }
    }
#endif
