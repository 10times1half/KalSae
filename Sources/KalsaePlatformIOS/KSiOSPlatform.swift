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
    public var autostart: (any KSAutostartBackend)? { _autostart }
    public var deepLink: (any KSDeepLinkBackend)? { _deepLink }

    private let _windows: KSiOSWindowBackend
    private let _dialogs: KSiOSDialogBackend
    private let _menus: KSiOSMenuBackend
    private let _notifications: KSiOSNotificationBackend
    private let _shell: KSiOSShellBackend
    private let _clipboard: KSiOSClipboardBackend
    private let _autostart: KSiOSAutostartBackend
    private let _deepLink: KSiOSDeepLinkBackend

    public init() {
        self.commandRegistry = KSCommandRegistry()
        self._windows = KSiOSWindowBackend()
        self._dialogs = KSiOSDialogBackend()
        self._menus = KSiOSMenuBackend()
        self._notifications = KSiOSNotificationBackend()
        self._shell = KSiOSShellBackend()
        self._clipboard = KSiOSClipboardBackend()
        self._autostart = KSiOSAutostartBackend()
        self._deepLink = KSiOSDeepLinkBackend(
            identifier: Bundle.main.bundleIdentifier ?? "kalsae")
    }

    public func run(
        config: KSConfig,
        configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
    ) async throws(KSError) -> Never {
        _ = config
        try await configure(self)
        throw KSError.unsupportedPlatform(
            "KSiOSPlatform.run is not wired; use KSApp.run()")
    }
}
#endif
