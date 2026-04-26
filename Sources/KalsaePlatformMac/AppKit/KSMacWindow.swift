#if os(macOS)
internal import AppKit
internal import Logging
public import KalsaeCore

/// Thin wrapper around `NSWindow` that mirrors `Win32Window` on the
/// Windows side. Knows how to host an `NSView` (the WKWebView) and exposes
/// a nonisolated `postJob` that forwards to the main queue — giving the
/// rest of the stack a single, platform-uniform way to hop back onto the
/// UI thread.
@MainActor
internal final class KSMacWindow {
    internal let nsWindow: NSWindow
    internal let config: KSWindowConfig

    private let log: Logger = KSLog.logger("platform.mac.window")

    init(config: KSWindowConfig) throws(KSError) {
        self.config = config

        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if config.resizable { style.insert(.resizable) }
        if !config.decorations {
            // 테두리 없는 윈도우: titled/closable/miniaturizable 스타일을 제거.
            style = [.borderless]
        }

        let rect = NSRect(
            x: 0, y: 0,
            width: CGFloat(config.width),
            height: CGFloat(config.height))
        let window = NSWindow(
            contentRect: rect,
            styleMask: style,
            backing: .buffered,
            defer: false)
        window.title = config.title
        if let minW = config.minWidth, let minH = config.minHeight {
            window.minSize = NSSize(width: CGFloat(minW),
                                    height: CGFloat(minH))
        }
        if let maxW = config.maxWidth, let maxH = config.maxHeight {
            window.maxSize = NSSize(width: CGFloat(maxW),
                                    height: CGFloat(maxH))
        }
        if config.center { window.center() }
        if config.alwaysOnTop { window.level = .floating }

        self.nsWindow = window
        log.info("NSWindow created: \(config.title) \(config.width)x\(config.height)")
    }

    /// Installs `view` as the window's content view and makes the window
    /// visible on screen if `visible == true` in the window config.
    func setContentView(_ view: NSView) {
        nsWindow.contentView = view
        if config.visible {
            nsWindow.makeKeyAndOrderFront(nil)
        }
    }

    /// Posts a closure onto the main queue. On macOS the default
    /// `MainActor` executor already cooperates with `RunLoop.main`, so
    /// this is mostly a parity shim with `Win32Window.postJob`.
    nonisolated func postJob(_ block: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { block() }
        }
    }
}
#endif
