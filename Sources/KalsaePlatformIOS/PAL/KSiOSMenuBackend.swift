#if os(iOS)
public import KalsaeCore

public struct KSiOSMenuBackend: KSMenuBackend, Sendable {
    public init() {}

    public func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) {
        _ = items
    }

    public func installWindowMenu(
        _ handle: KSWindowHandle,
        items: [KSMenuItem]
    ) async throws(KSError) {
        _ = (handle, items)
    }

    public func showContextMenu(
        _ items: [KSMenuItem],
        at point: KSPoint,
        in handle: KSWindowHandle?
    ) async throws(KSError) {
        _ = (items, point, handle)
    }
}
#endif
