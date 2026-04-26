#if os(Windows)
internal import WinSDK
internal import Logging
public import KalsaeCore
public import Foundation

/// Windows platform backend (Win32 HWND + WebView2 COM, Phase 1).
///
/// This is intentionally a thin Phase 1 implementation: it provides enough
/// surface area to prove end-to-end IPC works. Full PAL coverage (dialogs,
/// tray, menus, notifications, scheme handler) lands in later phases.
public final class KSWindowsPlatform: KSPlatform, @unchecked Sendable {
    public var name: String { "Windows (Win32 + WebView2)" }

    public let commandRegistry = KSCommandRegistry()

    /// Phase 8 PAL backends. The window backend is still a Phase-1 stub
    /// because multi-window support lives in Phase 11; everything else
    /// is fully wired against Win32.
    public var windows: any KSWindowBackend { _windows }
    public var dialogs: any KSDialogBackend { _dialogs }
    public var tray: (any KSTrayBackend)? { _tray }
    public var menus: any KSMenuBackend { _menus }
    public var notifications: any KSNotificationBackend { _notifications }
    public var shell: (any KSShellBackend)? { _shell }
    public var clipboard: (any KSClipboardBackend)? { _clipboard }
    public var accelerators: (any KSAcceleratorBackend)? { _accelerators }

    private let _windows = KSWindowsWindowBackend()
    private let _dialogs = KSWindowsDialogBackend()
    private let _menus   = KSWindowsMenuBackend()
    private let _tray    = KSWindowsTrayBackend()
    private let _notifications = KSWindowsNotificationBackend()
    private let _shell     = KSWindowsShellBackend()
    private let _clipboard = KSWindowsClipboardBackend()
    private let _accelerators = KSWindowsAcceleratorBackend()

    public init() {}

    public func run(
        config: KSConfig,
        configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
    ) async throws(KSError) -> Never {
        throw KSError(
            code: .unsupportedPlatform,
            message: "KSWindowsPlatform.run() lands in Phase 2 together with the full PAL. Use KSWindowsDemoHost for Phase 1 smoke tests.")
    }
}

// MARK: - Phase 1 stub for the still-unimplemented window backend

// 참고: `KSWindowsPlatform.windows`는 이제 실제 `KSWindowsWindowBackend`를
// 반환한다. 이전의 `NotImplementedBackend` 스터브는 제거되었다.
#endif
