#if os(macOS)
internal import AppKit
internal import Logging
public import KalsaeCore

@MainActor
public final class KSMacWindow {
    public let nsWindow: NSWindow
    public let config: KSWindowConfig
    public var webviewHost: WKWebViewHost?
    public private(set) var theme: KSWindowTheme = .system
    private var onBeforeCloseSwift: (@MainActor () -> Bool)?
    private var stateSaveSink: (@MainActor (KSPersistedWindowState) -> Void)?
    private let delegateProxy: WindowDelegateProxy

    private let log: Logger = KSLog.logger("platform.mac.window")

    public init(config: KSWindowConfig) throws(KSError) {
        self.config = config
        self.delegateProxy = WindowDelegateProxy()

        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if config.resizable { style.insert(.resizable) }
        if config.fullscreen { style.insert(.fullScreen) }
        if !config.decorations {
            style = [.borderless]
        }

        let rect = NSRect(x: 0, y: 0, width: CGFloat(config.width), height: CGFloat(config.height))
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.title = config.title
        if let minW = config.minWidth, let minH = config.minHeight {
            window.minSize = NSSize(width: CGFloat(minW), height: CGFloat(minH))
        }
        if let maxW = config.maxWidth, let maxH = config.maxHeight {
            window.maxSize = NSSize(width: CGFloat(maxW), height: CGFloat(maxH))
        }
        if config.center { window.center() }
        if config.alwaysOnTop { window.level = .floating }

        self.nsWindow = window
        self.delegateProxy.owner = self
        window.delegate = delegateProxy
        log.info("NSWindow created: \(config.title) \(config.width)x\(config.height)")
    }

    public func setContentView(_ view: NSView) {
        nsWindow.contentView = view
        if config.visible { nsWindow.makeKeyAndOrderFront(nil) }
    }

    nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { block() } }
    }

    // MARK: - 윈도우 조작

    public func show() { nsWindow.makeKeyAndOrderFront(nil) }
    public func hide() { nsWindow.orderOut(nil) }
    public func focus() { nsWindow.makeKeyAndOrderFront(nil) }
    public func close() { nsWindow.close() }
    public func setTitle(_ title: String) { nsWindow.title = title }

    public func setSize(width: Int, height: Int) {
        var frame = nsWindow.frame
        frame.size.width = CGFloat(width)
        frame.size.height = CGFloat(height)
        nsWindow.setFrame(frame, display: true, animate: false)
    }

    public func getSize() -> KSSize {
        let f = nsWindow.frame
        return KSSize(width: Int(f.width), height: Int(f.height))
    }

    public func setPosition(x: Int, y: Int) {
        let screenH = nsWindow.screen?.frame.height ?? 900
        var f = nsWindow.frame
        f.origin.x = CGFloat(x)
        f.origin.y = screenH - CGFloat(y) - f.height
        nsWindow.setFrame(f, display: true, animate: false)
    }

    public func getPosition() -> KSPoint {
        let f = nsWindow.frame
        let screenH = nsWindow.screen?.frame.height ?? 900
        return KSPoint(x: Double(f.origin.x), y: Double(screenH - f.origin.y - f.height))
    }

    public func setMinSize(width: Int, height: Int) { nsWindow.minSize = NSSize(width: CGFloat(width), height: CGFloat(height)) }
    public func setMaxSize(width: Int, height: Int) { nsWindow.maxSize = NSSize(width: CGFloat(width), height: CGFloat(height)) }
    public func centerOnScreen() { nsWindow.center() }
    public func minimize() { nsWindow.miniaturize(nil) }
    public func maximize() { nsWindow.zoom(nil) }
    public func restore() { nsWindow.deminiaturize(nil) }
    public func toggleMaximize() { nsWindow.zoom(nil) }
    public func isMinimized() -> Bool { nsWindow.isMiniaturized }
    public func isMaximized() -> Bool { nsWindow.isZoomed }
    public func isFullscreen() -> Bool { nsWindow.styleMask.contains(.fullScreen) }

    public func setFullscreen(_ enabled: Bool) {
        guard isFullscreen() != enabled else { return }
        nsWindow.toggleFullScreen(nil)
    }

    public func setAlwaysOnTop(_ enabled: Bool) {
        nsWindow.level = enabled ? .floating : .normal
    }

    public func setTheme(_ theme: KSWindowTheme) {
        self.theme = theme
        switch theme {
        case .dark:  nsWindow.appearance = NSAppearance(named: .darkAqua)
        case .light: nsWindow.appearance = NSAppearance(named: .aqua)
        case .system: nsWindow.appearance = nil
        }
    }

    public func setBackgroundColor(rgba: UInt32) {
        let a = CGFloat(rgba >> 24) / 255.0
        let r = CGFloat((rgba >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgba >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgba & 0xFF) / 255.0
        nsWindow.backgroundColor = NSColor(red: r, green: g, blue: b, alpha: a)
        webviewHost?.setBackgroundColor(NSColor(red: r, green: g, blue: b, alpha: a))
    }

    public func setCloseInterceptor(_ enabled: Bool) {
        webviewHost?.setCloseInterceptor(enabled)
    }

    public func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?) {
        onBeforeCloseSwift = cb
    }

    public func setWindowStateSaveSink(_ sink: (@MainActor (KSPersistedWindowState) -> Void)?) {
        stateSaveSink = sink
    }

    public func reload() {
        webviewHost?.webView.reload()
    }

    fileprivate func capturePersistedState() -> KSPersistedWindowState {
        let size = getSize()
        let pos = getPosition()
        return KSPersistedWindowState(
            x: Int(pos.x.rounded()),
            y: Int(pos.y.rounded()),
            width: size.width,
            height: size.height,
            maximized: isMaximized(),
            fullscreen: isFullscreen())
    }

    fileprivate func dispatchStateSave() {
        stateSaveSink?(capturePersistedState())
    }

    fileprivate func handleShouldClose() -> Bool {
        dispatchStateSave()
        if let cb = onBeforeCloseSwift, cb() == true {
            webviewHost?.emitBeforeCloseEvent()
            return false
        }
        if config.hideOnClose {
            webviewHost?.emitBeforeCloseEvent()
            hide()
            return false
        }
        if webviewHost?.isCloseInterceptorEnabled == true {
            webviewHost?.emitBeforeCloseEvent()
            return false
        }
        return true
    }

    fileprivate func handleDidMove() {
        dispatchStateSave()
    }

    fileprivate func handleDidResize() {
        dispatchStateSave()
    }
}

@MainActor
private final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    weak var owner: KSMacWindow?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        _ = sender
        return owner?.handleShouldClose() ?? true
    }

    func windowDidMove(_ notification: Notification) {
        _ = notification
        owner?.handleDidMove()
    }

    func windowDidResize(_ notification: Notification) {
        _ = notification
        owner?.handleDidResize()
    }
}
#endif