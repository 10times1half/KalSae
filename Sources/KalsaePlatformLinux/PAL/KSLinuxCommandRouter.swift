#if os(Linux)
public import KalsaeCore

/// Routes menu and tray command clicks to subscribers on Linux.
/// Mirrors `KSMacCommandRouter` / `KSWindowsCommandRouter`.
@MainActor
public final class KSLinuxCommandRouter {
    public static let shared = KSLinuxCommandRouter()

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
