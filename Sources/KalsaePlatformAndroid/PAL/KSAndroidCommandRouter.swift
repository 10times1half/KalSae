#if os(Android)
    public import KalsaeCore

    /// Routes menu (and future tray) command clicks to subscribers on Android.
    /// Mirrors `KSMacCommandRouter` / `KSWindowsCommandRouter` /
    /// `KSLinuxCommandRouter` so the per-platform menu backends emit through
    /// an identical shape.
    ///
    /// Subscribers are typically wired by `KSApp` so menu activations reach
    /// the same handlers that IPC `__ks.command(...)` calls do. On Android the
    /// dispatch happens after a `PopupMenu` selection is reported back via
    /// `KS_android_on_context_menu_result`.
    @MainActor
    public final class KSAndroidCommandRouter: KSMenuCommandRouting {
        public static let shared = KSAndroidCommandRouter()

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
