public import Foundation

/// PAL contract for the autostart ("launch on login") feature.
///
/// Platforms that implement this expose three operations: enable,
/// disable, and isEnabled. All three may run on the calling actor —
/// implementations are expected to be cheap (registry or plist edits).
///
/// - Windows: writes
///   `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\<identifier>`.
/// - macOS  : reserved (Login Items via `SMAppService` — not yet shipped).
/// - Linux  : reserved (XDG autostart `.desktop` file — not yet shipped).
public protocol KSAutostartBackend: Sendable {
    func enable() throws(KSError) -> Void
    func disable() throws(KSError) -> Void
    func isEnabled() -> Bool
}
