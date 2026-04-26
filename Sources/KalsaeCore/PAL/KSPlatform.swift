import Foundation

/// Opaque identifier for a live window. Platform layers provide concrete
/// handles that can be resolved to native objects (NSWindow, HWND, GtkWindow).
public struct KSWindowHandle: Hashable, Sendable {
    public let label: String
    public let rawValue: UInt64
    public init(label: String, rawValue: UInt64) {
        self.label = label
        self.rawValue = rawValue
    }
}

/// The top-level platform abstraction. Each OS provides exactly one conforming
/// type (e.g. `KSMacPlatform`, `KSWindowsPlatform`, `KSLinuxPlatform`).
///
/// The umbrella module picks the right one at compile time via `#if os(...)`.
public protocol KSPlatform: Sendable {
    /// Human-readable name of this backend, for logs.
    var name: String { get }

    /// Window backend for this platform.
    var windows: any KSWindowBackend { get }

    /// Dialog backend (file/save/folder/message).
    var dialogs: any KSDialogBackend { get }

    /// Tray (status item) backend. Optional because not every environment
    /// supports it (e.g. some Wayland compositors).
    var tray: (any KSTrayBackend)? { get }

    /// Native menu backend.
    var menus: any KSMenuBackend { get }

    /// Notifications backend.
    var notifications: any KSNotificationBackend { get }

    /// Operating-system shell integration (open external URL, reveal in
    /// file manager, move to trash). Optional: platforms that haven't
    /// implemented a shell backend yet may return `nil`.
    var shell: (any KSShellBackend)? { get }

    /// System clipboard. Optional for the same reason as `shell`.
    var clipboard: (any KSClipboardBackend)? { get }

    /// Global keyboard accelerator (hot-key) backend. Optional: not
    /// every platform supports global hot-keys (e.g. sandboxed contexts).
    var accelerators: (any KSAcceleratorBackend)? { get }

    /// Bootstraps the native application (NSApplication / Win32 message loop /
    /// GApplication) and runs it until exit.
    ///
    /// - Parameter configure: Invoked after the platform is initialized but
    ///                        before the run loop takes over.
    func run(
        config: KSConfig,
        configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
    ) async throws(KSError) -> Never
}

// MARK: - Source-compatible defaults

extension KSPlatform {
    /// Default: platform doesn't expose a shell backend yet.
    public var shell: (any KSShellBackend)? { nil }

    /// Default: platform doesn't expose a clipboard backend yet.
    public var clipboard: (any KSClipboardBackend)? { nil }

    /// Default: platform doesn't expose a global accelerator backend yet.
    public var accelerators: (any KSAcceleratorBackend)? { nil }
}
