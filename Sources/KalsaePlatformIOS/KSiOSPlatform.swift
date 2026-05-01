#if os(iOS)
internal import UIKit
public import KalsaeCore
public import Foundation

// @unchecked: UIKit main thread confinement — actor unsuitable for @UIApplicationMain binding
public final class KSiOSPlatform: KSPlatform, @unchecked Sendable {
    public var name: String { "iOS (UIKit + WKWebView)" }

    public let commandRegistry: KSCommandRegistry

    public var windows: any KSWindowBackend { _windows }
    public var dialogs: any KSDialogBackend { _dialogs }
    public var tray: (any KSTrayBackend)? { nil }
    public var menus: any KSMenuBackend { _menus }
    public var notifications: any KSNotificationBackend { _notifications }
    public var shell: (any KSShellBackend)? { _shell }
    public var clipboard: (any KSClipboardBackend)? { _clipboard }
    public var accelerators: (any KSAcceleratorBackend)? { nil }

    private let _windows: KSiOSWindowBackend
    private let _dialogs: KSiOSDialogBackend
    private let _menus: KSiOSMenuBackend
    private let _notifications: KSiOSNotificationBackend
    private let _shell: KSiOSShellBackend
    private let _clipboard: KSiOSClipboardBackend

    public init() {
        self.commandRegistry = KSCommandRegistry()
        self._windows = KSiOSWindowBackend()
        self._dialogs = KSiOSDialogBackend()
        self._menus = KSiOSMenuBackend()
        self._notifications = KSiOSNotificationBackend()
        self._shell = KSiOSShellBackend()
        self._clipboard = KSiOSClipboardBackend()
    }

    public func run(
        config: KSConfig,
        configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
    ) async throws(KSError) -> Never {
        _ = config
        try await configure(self)
        fatalError("KSiOSPlatform.run is not wired yet")
    }
}
#endif
