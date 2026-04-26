import Foundation

/// Installs the application/window/context menus described in
/// `KSMenuConfig`.
public protocol KSMenuBackend: Sendable {
    func installAppMenu(_ items: [KSMenuItem]) async throws(KSError)
    func installWindowMenu(_ handle: KSWindowHandle,
                           items: [KSMenuItem]) async throws(KSError)

    /// Shows a context menu at the given screen-relative point.
    func showContextMenu(_ items: [KSMenuItem],
                         at point: KSPoint,
                         in handle: KSWindowHandle?) async throws(KSError)
}

public struct KSPoint: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
