public import Foundation

/// Operating-system shell integration: opening URLs in the user's default
/// browser, revealing files in the OS file manager, moving items to the
/// trash, etc.
///
/// Methods on this protocol carry side effects on the user's machine and
/// should be gated by the application's `security.shell` allowlist (added
/// in a follow-up phase). All implementations are expected to run any
/// native UI work on the platform UI thread.
public protocol KSShellBackend: Sendable {
    /// Opens `url` with the system's registered default handler.
    /// Equivalent to Wails' `BrowserOpenURL`.
    func openExternal(_ url: URL) async throws(KSError)

    /// Reveals `url` (a file or folder) in the platform's file manager
    /// (Explorer / Finder / Files), selecting the item when possible.
    func showItemInFolder(_ url: URL) async throws(KSError)

    /// Moves `url` to the platform Recycle Bin / Trash. The file system
    /// entry is not permanently deleted.
    func moveToTrash(_ url: URL) async throws(KSError)
}

/// Default no-op implementations: every method throws
/// `unsupportedPlatform`. Platforms opt in by overriding individual
/// methods.
extension KSShellBackend {
    @inline(__always)
    private func _unsupportedThrow(_ op: String) throws(KSError) -> Never {
        throw KSError(code: .unsupportedPlatform,
                      message: "KSShellBackend.\(op) is not implemented on this platform.")
    }

    public func openExternal(_ url: URL) async throws(KSError) { try _unsupportedThrow("openExternal") }
    public func showItemInFolder(_ url: URL) async throws(KSError) { try _unsupportedThrow("showItemInFolder") }
    public func moveToTrash(_ url: URL) async throws(KSError) { try _unsupportedThrow("moveToTrash") }
}
