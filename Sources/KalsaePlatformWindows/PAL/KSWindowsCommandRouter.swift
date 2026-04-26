#if os(Windows)
internal import WinSDK
public import KalsaeCore
public import Foundation

/// Routes menu / tray commands back to subscribers. The platform layer
/// (or the demo) installs a single sink that forwards to the JS bridge,
/// the command registry, or both.
@MainActor
public final class KSWindowsCommandRouter {
    public static let shared = KSWindowsCommandRouter()

    public typealias Sink = @MainActor (_ command: String, _ itemID: String?) -> Void
    private var sinks: [Sink] = []

    private init() {}

    /// Adds a command subscriber. Called for every menu / tray click that
    /// has a non-`nil` `KSMenuItem.command`.
    public func subscribe(_ sink: @escaping Sink) {
        sinks.append(sink)
    }

    public func clear() {
        sinks.removeAll()
    }

    internal func dispatch(command: String, itemID: String?) {
        for sink in sinks { sink(command, itemID) }
    }
}
#endif
