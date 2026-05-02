#if os(Windows)
    internal import WinSDK
    public import KalsaeCore

    extension Win32Window {

        /// Returns true when this window is currently in fullscreen mode
        /// (as managed by `setFullscreen(_:)`).
        func isFullscreen() -> Bool {
            // Win32에는 1급 "전체화면" 플래그가 없으므로 수동으로 추적한다.
            // `setFullscreen`이 저장한 스타일 백업으로 추론한다.
            savedFullscreenStyle != nil
        }

        /// Toggles fullscreen mode by stripping the window chrome and
        /// resizing to the nearest monitor's `rcMonitor`. Stores the prior
        /// style/placement so `setFullscreen(false)` can restore exactly.
        func setFullscreen(_ enabled: Bool) {
            guard let hwnd else { return }
            if enabled {
                if savedFullscreenStyle != nil { return }
                let style = GetWindowLongPtrW(hwnd, GWL_STYLE)
                let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
                var placement = WINDOWPLACEMENT()
                placement.length = UINT(MemoryLayout<WINDOWPLACEMENT>.size)
                _ = GetWindowPlacement(hwnd, &placement)
                savedFullscreenStyle = (style, ex, placement)

                let monitor = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST))
                var info = MONITORINFO()
                info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
                _ = GetMonitorInfoW(monitor, &info)
                let rc = info.rcMonitor

                let wsOverlappedWindowStyleMask: LONG_PTR = LONG_PTR(WS_OVERLAPPEDWINDOW)
                _ = SetWindowLongPtrW(hwnd, GWL_STYLE, style & ~wsOverlappedWindowStyleMask)
                _ = SetWindowPos(
                    hwnd, nil,
                    rc.left, rc.top,
                    rc.right - rc.left, rc.bottom - rc.top,
                    UINT(SWP_NOZORDER) | UINT(SWP_NOOWNERZORDER) | UINT(SWP_FRAMECHANGED))
            } else {
                guard let saved = savedFullscreenStyle else { return }
                _ = SetWindowLongPtrW(hwnd, GWL_STYLE, saved.style)
                _ = SetWindowLongPtrW(hwnd, GWL_EXSTYLE, saved.ex)
                var placement = saved.placement
                _ = SetWindowPlacement(hwnd, &placement)
                _ = SetWindowPos(
                    hwnd, nil, 0, 0, 0, 0,
                    UINT(SWP_NOMOVE) | UINT(SWP_NOSIZE) | UINT(SWP_NOZORDER) | UINT(SWP_NOOWNERZORDER)
                        | UINT(SWP_FRAMECHANGED))
                savedFullscreenStyle = nil
            }
        }
    }
#endif
