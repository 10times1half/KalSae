#if os(Windows)
internal import WinSDK

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
        // Win32에는 윈도우 클래스 브러시 밖에 HWND 자체의 배경색이 없다.
        // 커스텀 브러시로 재그림하려면 WM_ERASEBKGND를 서브클래스싱해야
        // 해서 보류한다. 우선 no-op으로 두어 호출자가 플랫폼 분기를
        // 두지 않아도 되도록 한다.
        _ = rgba
    }

    func reload() {
        webviewHost?.reload()
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
}
#endif
