#if os(Windows)
internal import WinSDK
public import KalsaeCore

// MARK: - Win32Window window state operations
//
// Win32Window의 윈도우 표시 상태(최소화/최대화/복원/AlwaysOnTop/중앙
// 정렬/배경색)를 모은 확장. 메인 파일은 생성/소멸/포커스/크기 같은
// 핵심 라이프사이클에 집중하고, 이 확장은 Phase 1에서 도입한
// `KSWindowState` PAL 매핑 메서드들을 담당한다.

extension Win32Window {

    // MARK: - Window state

    func minimize() {
        guard let hwnd else { return }
        _ = ShowWindow(hwnd, SW_MINIMIZE)
    }

    func maximize() {
        guard let hwnd else { return }
        _ = ShowWindow(hwnd, SW_MAXIMIZE)
    }

    func restore() {
        guard let hwnd else { return }
        _ = ShowWindow(hwnd, SW_RESTORE)
    }

    func toggleMaximize() {
        guard let hwnd else { return }
        if IsZoomed(hwnd) {
            _ = ShowWindow(hwnd, SW_RESTORE)
        } else {
            _ = ShowWindow(hwnd, SW_MAXIMIZE)
        }
    }

    func isMinimized() -> Bool {
        guard let hwnd else { return false }
        return IsIconic(hwnd)
    }

    func isMaximized() -> Bool {
        guard let hwnd else { return false }
        return IsZoomed(hwnd)
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        guard let hwnd else { return }
        let after: HWND? = enabled
            ? HWND(bitPattern: -1) // HWND_TOPMOST
            : HWND(bitPattern: -2) // HWND_NOTOPMOST
        _ = SetWindowPos(
            hwnd, after, 0, 0, 0, 0,
            UINT(SWP_NOMOVE) | UINT(SWP_NOSIZE) | UINT(SWP_NOACTIVATE))
    }

    func centerOnScreen() {
        guard let hwnd else { return }
        var rc = RECT()
        _ = GetWindowRect(hwnd, &rc)
        let w = rc.right - rc.left
        let h = rc.bottom - rc.top

        let monitor = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST))
        var info = MONITORINFO()
        info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        _ = GetMonitorInfoW(monitor, &info)
        let work = info.rcWork

        let x = work.left + ((work.right - work.left) - w) / 2
        let y = work.top  + ((work.bottom - work.top) - h) / 2
        _ = SetWindowPos(hwnd, nil, x, y, 0, 0,
                         UINT(SWP_NOSIZE) | UINT(SWP_NOZORDER))
    }

    func setBackgroundColor(rgba: UInt32) {
        guard let hwnd else { return }
        // 우리는 RGBA(0xRRGGBBAA)를 받지만 Win32 `COLORREF`는 0x00BBGGRR
        // (alpha 무시). Wails 패리티: 알파 0/255만 의미가 있어 0이 아니면
        // 255처럼 취급. 알파=0(완전 투명)은 layered window가 필요하므로
        // 솔리드 브러시로 폴백 — 향후 Phase C의 `transparent` 옵션에서
        // 처리한다.
        let r = UInt8((rgba >> 24) & 0xFF)
        let g = UInt8((rgba >> 16) & 0xFF)
        let b = UInt8((rgba >> 8) & 0xFF)
        let cref: COLORREF = (COLORREF(b) << 16) | (COLORREF(g) << 8) | COLORREF(r)

        // 새 브러시를 만든 뒤에야 이전 것을 풀어 GDI leak을 회피한다.
        let newBrush = CreateSolidBrush(cref)
        let old = backgroundBrush
        backgroundBrush = newBrush
        if let old { _ = DeleteObject(old) }

        // 즉시 다시 그리도록 클라이언트 영역 무효화. WebView2가 가린
        // 영역은 어차피 WebView2가 다시 그리지만, 리사이즈 중 노출되는
        // 가장자리는 새 색으로 칠해진다.
        _ = InvalidateRect(hwnd, nil, true)
    }

    func reload() {
        webviewHost?.reload()
    }

    /// Toggles WM_CLOSE interception. When `enabled` is `true`, the X
    /// button / Alt-F4 emits `__ks.window.beforeClose` instead of
    /// closing. JS calls `__ks.window.close` to actually close.
    func setCloseInterceptor(_ enabled: Bool) {
        closeInterceptEnabled = enabled
    }

    /// Begins a non-client drag of this window from the current mouse
    /// position, mimicking a click on the title bar. Used by the JS
    /// drag-region (`app-region: drag`) hit-test in `KSRuntimeJS`.
    ///
    /// Implementation: release any active mouse capture, then post a
    /// `WM_NCLBUTTONDOWN` with `HTCAPTION` so DefWindowProc enters its
    /// move modal loop. Posting (rather than sending) avoids re-entering
    /// the WebView2 message handler synchronously.
    func startDrag() {
        guard let hwnd else { return }
        _ = ReleaseCapture()
        _ = PostMessageW(hwnd, UINT(WM_NCLBUTTONDOWN), WPARAM(HTCAPTION), 0)
    }

    /// Requests a Windows 11 system backdrop on this window via
    /// `DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE)` (attribute
    /// `38`, available on build ≥ 22621). On older builds the call
    /// returns a non-zero HRESULT and is silently ignored — the window
    /// keeps its solid background.
    ///
    /// Mapping (from `DWM_SYSTEMBACKDROP_TYPE`):
    ///   - `.auto`    → 0 (DWMSBT_AUTO)
    ///   - `.none`    → 1 (DWMSBT_NONE)
    ///   - `.mica`    → 2 (DWMSBT_MAINWINDOW)
    ///   - `.acrylic` → 3 (DWMSBT_TRANSIENTWINDOW)
    ///   - `.tabbed`  → 4 (DWMSBT_TABBEDWINDOW)
    func setSystemBackdrop(_ kind: KSWindowBackdrop) {
        guard let hwnd else { return }
        var value: Int32
        switch kind {
        case .auto:    value = 0
        case .none:    value = 1
        case .mica:    value = 2
        case .acrylic: value = 3
        case .tabbed:  value = 4
        }
        // DWMWA_SYSTEMBACKDROP_TYPE = 38
        _ = withUnsafePointer(to: &value) { ptr in
            DwmSetWindowAttribute(hwnd, DWORD(38), ptr, DWORD(MemoryLayout<Int32>.size))
        }
    }
}
#endif
