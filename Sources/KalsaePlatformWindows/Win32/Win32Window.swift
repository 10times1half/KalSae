#if os(Windows)
internal import WinSDK
public import KalsaeCore

/// Wraps a single Win32 HWND. Hosts exactly one WebView2 controller.
///
/// Lifecycle:
///   init(config:) → CreateWindowExW → register with Win32App
///   attach(host:) → WebView2 host takes responsibility for resizing
///   show(), close(), ...
@MainActor
internal final class Win32Window {
    let label: String
    // `hwnd`는 init에서 UI 스레드에 설정되고 WM_DESTROY(역시 UI
    // 스레드)에서 제거된다. `postJob` 경로로 백그라운드 스레드가
    // 읽는다. PostMessageW는 스레드 안전하고 파괴된 윈도우에 대해서도
    // 해롭지 않아 조금 올될 수도 있지만 유효한 HWND 읽기는 괜찮다.
    // 확장 파일(`Win32Window+WndProc.swift`)에서 WM_DESTROY 처리 시
    // 정리(nil 대입)해야 하므로 internal(set)로 둔다.
    nonisolated(unsafe) internal(set) var hwnd: HWND?
    internal(set) var webviewHost: WebView2Host?
    private let log = KSLog.logger("platform.windows.window")

    init(config: KSWindowConfig) throws(KSError) {
        self.label = config.label
        try Win32App.shared.ensureWindowClassRegistered()

        let className = "KalsaeWindow"
        // 베이스 스타일에 config의 frame/resize 옵션을 반영한다.
        // - decorations=false → frameless(WS_POPUP), `setFullscreen` 등이
        //   복원할 수 있도록 WS_BORDER만 유지한다.
        // - resizable=false → WS_THICKFRAME/WS_MAXIMIZEBOX 제거.
        var rawStyle: UInt32 = UInt32(WS_OVERLAPPEDWINDOW)
        if !config.decorations {
            // WS_POPUP | WS_SYSMENU 정도만 남기고 caption/borders 제거.
            rawStyle = UInt32(WS_POPUP) | UInt32(WS_SYSMENU)
        }
        if !config.resizable {
            rawStyle &= ~UInt32(WS_THICKFRAME)
            rawStyle &= ~UInt32(WS_MAXIMIZEBOX)
        }
        let style = DWORD(rawStyle)
        // alwaysOnTop은 ex-style WS_EX_TOPMOST로 처음부터 적용한다.
        var exStyle: DWORD = 0
        if config.alwaysOnTop {
            exStyle |= DWORD(WS_EX_TOPMOST)
        }

        let hwnd = className.withUTF16Pointer { cls -> HWND? in
            config.title.withUTF16Pointer { title -> HWND? in
                CreateWindowExW(
                    exStyle,
                    cls,
                    title,
                    style,
                    Int32(CW_USEDEFAULT), Int32(CW_USEDEFAULT),
                    Int32(config.width), Int32(config.height),
                    nil,    // parent
                    nil,    // menu
                    Win32App.shared.instanceHandle,
                    nil)
            }
        }
        guard let hwnd else {
            throw KSError(
                code: .windowCreationFailed,
                message: "CreateWindowExW failed (GetLastError=\(GetLastError()))")
        }
        self.hwnd = hwnd
        Win32App.shared.register(self)
        KSWin32HandleRegistry.shared.register(label: config.label, hwnd: hwnd)
        KSWin32MainWindowTracker.shared.track(hwnd: hwnd)
        log.info("Created window '\(config.label)' hwnd=\(hwnd)")

        // Phase C 옵션 적용 — 모두 보일러플레이트 Win32 호출.
        if let bg = config.backgroundColor {
            let rgba = (UInt32(bg.r & 0xFF) << 24)
                     | (UInt32(bg.g & 0xFF) << 16)
                     | (UInt32(bg.b & 0xFF) << 8)
                     |  UInt32(bg.a & 0xFF)
            setBackgroundColor(rgba: rgba)
        }
        if config.disableWindowIcon {
            // big/small 아이콘 모두 비운다. 작업 표시줄은 EXE 아이콘으로 폴백.
            _ = SendMessageW(hwnd, UINT(WM_SETICON), WPARAM(ICON_SMALL), 0)
            _ = SendMessageW(hwnd, UINT(WM_SETICON), WPARAM(ICON_BIG), 0)
        }
        if config.contentProtection {
            // WDA_EXCLUDEFROMCAPTURE = 0x11(=17). 구버전에선 false 반환하고 끝.
            _ = SetWindowDisplayAffinity(hwnd, DWORD(0x11))
        }
        if config.hideOnClose {
            // close 인터셉터 켜고 sink가 hideOnClose 분기를 처리한다.
            // sink가 비어있는 단계라면 WM_CLOSE → 기본 destroy로 떨어진다.
            self.closeInterceptEnabled = true
            self.hideOnClose = true
        }
        if config.center {
            centerOnScreen()
        }

        // 표시는 마지막에. startState가 있으면 그에 맞춰 표시,
        // 없으면 fullscreen 플래그(레거시) 또는 visible 플래그를 따른다.
        let state: KSWindowStartState? = config.startState
            ?? (config.fullscreen ? .fullscreen : nil)
        if let state {
            switch state {
            case .normal:
                if config.visible { show() }
            case .maximized:
                _ = ShowWindow(hwnd, SW_SHOWMAXIMIZED)
            case .minimized:
                _ = ShowWindow(hwnd, SW_SHOWMINIMIZED)
            case .fullscreen:
                if config.visible { show() }
                setFullscreen(true)
            }
        } else if config.visible {
            show()
        }
    }

    // MARK: - Simple operations

    func show() {
        guard let hwnd else { return }
        _ = ShowWindow(hwnd, SW_SHOW)
        _ = UpdateWindow(hwnd)
    }

    func hide() {
        guard let hwnd else { return }
        _ = ShowWindow(hwnd, SW_HIDE)
    }

    func focus() {
        guard let hwnd else { return }
        _ = SetForegroundWindow(hwnd)
        _ = SetFocus(hwnd)
    }

    func setTitle(_ title: String) {
        guard let hwnd else { return }
        title.withUTF16Pointer { _ = SetWindowTextW(hwnd, $0) }
    }

    func close() {
        guard let hwnd else { return }
        _ = DestroyWindow(hwnd)
    }

    // MARK: - Window state — see `Win32Window+State.swift`.

    /// Saved style/placement for restoring out of fullscreen mode. Held
    /// at module visibility so `Win32Window+Fullscreen.swift` can reach
    /// it across files.
    internal var savedFullscreenStyle: (style: LONG_PTR, ex: LONG_PTR, placement: WINDOWPLACEMENT)?

    // MARK: - Geometry

    func setPosition(x: Int, y: Int) {
        guard let hwnd else { return }
        _ = SetWindowPos(hwnd, nil, Int32(x), Int32(y), 0, 0,
                         UINT(SWP_NOSIZE) | UINT(SWP_NOZORDER))
    }

    func getPosition() -> (x: Int, y: Int) {
        guard let hwnd else { return (0, 0) }
        var rc = RECT()
        _ = GetWindowRect(hwnd, &rc)
        return (Int(rc.left), Int(rc.top))
    }

    func getSize() -> (width: Int, height: Int) {
        guard let hwnd else { return (0, 0) }
        var rc = RECT()
        _ = GetWindowRect(hwnd, &rc)
        return (Int(rc.right - rc.left), Int(rc.bottom - rc.top))
    }

    func setSize(width: Int, height: Int) {
        guard let hwnd else { return }
        _ = SetWindowPos(hwnd, nil, 0, 0, Int32(width), Int32(height),
                         UINT(SWP_NOMOVE) | UINT(SWP_NOZORDER))
    }

    /// Min/max client constraints applied via WM_GETMINMAXINFO.
    var minSize: (width: Int, height: Int)?
    var maxSize: (width: Int, height: Int)?

    /// Per-window background brush used by WM_ERASEBKGND. `nil` means
    /// "fall through to DefWindowProc" (use the class brush).
    /// Owned by this window — released in `dispose()`/WM_DESTROY.
    internal var backgroundBrush: HBRUSH?

    /// Sink invoked by `WNDPROC` to surface window/system events to the
    /// JS side. Demo host wires this to `WebView2Bridge.emit`. Optional —
    /// when `nil`, events are simply dropped.
    internal var eventSink: (@MainActor (String, any Encodable & Sendable) -> Void)?

    /// When `true`, `WM_CLOSE` is suppressed and a
    /// `__ks.window.beforeClose` event is emitted instead. JS must call
    /// `__ks.window.close` (or set the interceptor back to `false`) to
    /// actually close the window.
    internal var closeInterceptEnabled: Bool = false

    /// Tray-style behaviour: on `WM_CLOSE`, hide the window instead of
    /// destroying it. Wins over `closeInterceptEnabled` only when the
    /// interceptor is the implicit one set up by this flag.
    internal var hideOnClose: Bool = false

    /// Last observed minimize/maximize/restore state — used to debounce
    /// `WM_SIZE` so that we don't emit the same transition twice.
    internal var lastSizeState: Int32 = SIZE_RESTORED

    // MARK: - Phase C4 native lifecycle hooks
    //
    // Optional Swift-level callbacks invoked from `WndProc` in addition
    // to the JS event emit. Set by the demo host on behalf of `KSApp`.

    /// Invoked from `WM_CLOSE`. Return `true` to cancel the close
    /// (window stays open); return `false` (or leave `nil`) to fall
    /// through to the existing intercept / hideOnClose / DefWindowProc
    /// chain. Always called *before* the JS `__ks.window.beforeClose`
    /// event is emitted.
    internal var onBeforeCloseSwift: (@MainActor () -> Bool)?

    /// Invoked from `WM_POWERBROADCAST` (PBT_APMSUSPEND). Best-effort:
    /// the system may signal suspend after the process has been frozen,
    /// in which case the callback never runs.
    internal var onSuspendSwift: (@MainActor () -> Void)?

    /// Invoked from `WM_POWERBROADCAST`
    /// (PBT_APMRESUMEAUTOMATIC / PBT_APMRESUMESUSPEND).
    internal var onResumeSwift: (@MainActor () -> Void)?

    func setMinSize(width: Int, height: Int) {
        minSize = (width, height)
    }

    func setMaxSize(width: Int, height: Int) {
        maxSize = (width, height)
    }

    // `reload`, `startDrag`, `setBackgroundColor` — see `Win32Window+State.swift`.

    func attach(host: WebView2Host) {
        self.webviewHost = host
        host.ownerWindow = self
        resizeWebViewToClient()
    }

    internal func resizeWebViewToClient() {
        guard let hwnd, let webviewHost else { return }
        var rc = RECT()
        _ = GetClientRect(hwnd, &rc)
        webviewHost.setBounds(
            x: Int(rc.left),
            y: Int(rc.top),
            width: Int(rc.right - rc.left),
            height: Int(rc.bottom - rc.top))
    }

    // MARK: - UI-thread job dispatch
    //
    // Win32 `GetMessageW` 메시지 루프가 Swift 협동 실행기를 펄프하지
    // 않으므로 백그라운드에서 `Task { @MainActor in ... }`를 그대로 쓸
    // 수 없다. 대신 사용자 정의 윈도우 메시지를 감싸 UI 스레드에
    // 포스트하고, `WNDPROC`에서 실행한다.
    static let WM_KS_JOB: UINT = UINT(WM_USER) + 1

    /// Posts a closure onto this window's UI thread. Safe to call from
    /// any thread because `PostMessageW` is thread-safe and the retain box
    /// is a non-isolated class.
    nonisolated func postJob(_ block: @escaping @MainActor () -> Void) {
        guard let hwnd else { return }
        ksPostUIJob(hwnd: hwnd, block: block)
    }

    // MARK: - Window procedure — see `Win32Window+WndProc.swift`.
}
#endif
