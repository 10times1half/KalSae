public import Foundation

/// Global keyboard accelerator (hot-key) registration.
///
/// On Windows this maps to `RegisterHotKey` / `WM_HOTKEY` (system-wide
/// shortcuts that fire even when the application is unfocused).
/// macOS / Linux implementations land in later phases.
///
/// Accelerator strings use the same cross-platform notation as
/// `KSMenuItem.accelerator`, e.g.:
/// - `"CmdOrCtrl+Shift+N"` → `Ctrl+Shift+N` on Windows/Linux
/// - `"Alt+F4"`, `"Ctrl+Space"`, `"F11"`, `"Ctrl+Plus"`
public protocol KSAcceleratorBackend: Sendable {
    /// Registers `accelerator` and binds it to `handler`. The same `id`
    /// can be re-registered (the prior binding is replaced first).
    /// - Throws: `KSError` with code `.invalidArgument` for unparseable
    ///   accelerators, `.platformInitFailed` if the OS rejects the
    ///   registration (e.g. another process already owns the hot-key).
    func register(id: String,
                  accelerator: String,
                  _ handler: @Sendable @escaping () -> Void) async throws(KSError)

    /// Unregisters the binding previously installed for `id`. No-op if
    /// `id` is unknown.
    func unregister(id: String) async throws(KSError)

    /// Removes every registration owned by this backend.
    func unregisterAll() async throws(KSError)
}

extension KSAcceleratorBackend {
    @inline(__always)
    private func _unsupported(_ op: String) throws(KSError) -> Never {
        throw KSError(code: .unsupportedPlatform,
                      message: "KSAcceleratorBackend.\(op) is not implemented on this platform.")
    }

    public func register(id: String,
                         accelerator: String,
                         _ handler: @Sendable @escaping () -> Void) async throws(KSError) {
        try _unsupported("register")
    }

    public func unregister(id: String) async throws(KSError) {
        try _unsupported("unregister")
    }

    public func unregisterAll() async throws(KSError) {
        try _unsupported("unregisterAll")
    }
}
