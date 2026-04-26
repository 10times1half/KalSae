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
        let style = DWORD(WS_OVERLAPPEDWINDOW)
        let exStyle: DWORD = 0

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

        if config.visible {
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
