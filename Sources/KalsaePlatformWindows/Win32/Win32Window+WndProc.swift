#if os(Windows)
internal import WinSDK

// MARK: - Win32Window WNDPROC dispatch
//
// `Win32Window.handle(msg:wparam:lparam:)`는 클래스 등록 시 설치한
// 글로벌 WNDPROC가 메시지를 이 인스턴스로 라우팅한 뒤 호출된다.
// 핵심 메시지(WM_KS_JOB, WM_SIZE, WM_GETMINMAXINFO, WM_COMMAND,
// WM_DESTROY)만 직접 처리하고 나머지는 DefWindowProcW로 위임한다.

extension Win32Window {

    func handle(msg: UINT, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
        if msg == Self.WM_KS_JOB {
            let ptr = UnsafeMutableRawPointer(
                bitPattern: UInt(wparam))
            if let ptr {
                let box = Unmanaged<_KBUIJobPlainBox>.fromOpaque(ptr)
                    .takeRetainedValue()
                box.block()
            }
            return 0
        }
        switch Int32(msg) {
        case WM_SIZE:
            resizeWebViewToClient()
            // wparam이 SIZE_MINIMIZED/SIZE_MAXIMIZED/SIZE_RESTORED를
            // 알려주므로 상태 전이가 있을 때만 minimize/maximize/restore
            // 이벤트를 발사한다. resize 이벤트는 매번 발사하되 페이로드는
            // 새 클라이언트 크기.
            let state = Int32(wparam)
            if state != lastSizeState {
                switch state {
                case SIZE_MINIMIZED:
                    emit("__ks.window.minimize", EmptyPayload())
                case SIZE_MAXIMIZED:
                    emit("__ks.window.maximize", EmptyPayload())
                case SIZE_RESTORED:
                    if lastSizeState == SIZE_MINIMIZED || lastSizeState == SIZE_MAXIMIZED {
                        emit("__ks.window.restore", EmptyPayload())
                    }
                default:
                    break
                }
                lastSizeState = state
            }
            // SIZE_RESTORED일 때만 의미 있는 새 크기. 최소화 시
            // (0,0)이 들어와 노이즈가 되므로 거른다.
            if state == SIZE_RESTORED || state == SIZE_MAXIMIZED {
                let w = Int(lparam & 0xFFFF)
                let h = Int((lparam >> 16) & 0xFFFF)
                emit("__ks.window.resize", WindowSizePayload(w: w, h: h))
            }
            return 0

        case WM_MOVE:
            // LOWORD/HIWORD는 클라이언트 영역 좌상단의 화면 좌표(부호 있음).
            let x = Int16(truncatingIfNeeded: lparam & 0xFFFF)
            let y = Int16(truncatingIfNeeded: (lparam >> 16) & 0xFFFF)
            emit("__ks.window.move",
                 WindowPointPayload(x: Int(x), y: Int(y)))
            return DefWindowProcW(hwnd, msg, wparam, lparam)

        case WM_ACTIVATE:
            let activeState = Int32(wparam & 0xFFFF)
            if activeState == WA_INACTIVE {
                emit("__ks.window.blur", EmptyPayload())
            } else {
                emit("__ks.window.focus", EmptyPayload())
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam)

        case WM_DPICHANGED:
            let dpi = Int((wparam >> 16) & 0xFFFF)  // HIWORD = Y-DPI(=X-DPI)
            let scale = Double(dpi) / 96.0
            // OS가 새 권장 사각형을 lparam(RECT*)로 넘긴다 — 수용한다.
            if let rectPtr = UnsafeMutablePointer<RECT>(
                bitPattern: UInt(lparam)), let hwnd
            {
                let r = rectPtr.pointee
                _ = SetWindowPos(
                    hwnd, nil,
                    r.left, r.top,
                    r.right - r.left, r.bottom - r.top,
                    UINT(SWP_NOZORDER) | UINT(SWP_NOACTIVATE))
            }
            emit("__ks.system.dpiChanged",
                 DPIPayload(dpi: dpi, scale: scale))
            return 0

        case WM_SETTINGCHANGE:
            // lparam은 변경된 설정 이름의 와이드 문자열. "ImmersiveColorSet"이면
            // 다크/라이트 모드 토글이다. 그 외는 무시.
            if let cstr = UnsafePointer<UInt16>(bitPattern: UInt(lparam)) {
                let name = String(decodingCString: cstr, as: UTF16.self)
                if name == "ImmersiveColorSet" {
                    let theme = readSystemAppsTheme()
                    emit("__ks.system.themeChanged",
                         ThemePayload(theme: theme))
                }
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam)

        case WM_POWERBROADCAST:
            // PBT_APMSUSPEND = 0x0004, PBT_APMRESUMEAUTOMATIC = 0x0012,
            // PBT_APMRESUMESUSPEND = 0x0007 (사용자 입력으로 재시작).
            switch Int32(wparam) {
            case 0x0004:
                emit("__ks.system.suspend", EmptyPayload())
            case 0x0012, 0x0007:
                emit("__ks.system.resume", EmptyPayload())
            default:
                break
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam)

        case WM_CLOSE:
            // 인터셉트가 켜진 경우 close를 취소하고 JS에 알린다.
            // JS는 `__ks.window.close`를 호출해 강제 종료하거나,
            // 인터셉터를 끄고 close를 다시 보낼 수 있다.
            if closeInterceptEnabled {
                emit("__ks.window.beforeClose", EmptyPayload())
                return 0
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam)

        case WM_ERASEBKGND:
            // 사용자 브러시가 설정된 경우 클라이언트 영역을 그 색으로
            // 채우고 처리됨을 알린다(0이 아닌 값 반환). 미설정 시 기본
            // 처리(클래스 브러시)에 위임한다.
            if let brush = backgroundBrush, let hwnd {
                let hdc = HDC(bitPattern: UInt(lparam))
                if let hdc {
                    var rc = RECT()
                    _ = GetClientRect(hwnd, &rc)
                    _ = FillRect(hdc, &rc, brush)
                    return 1
                }
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam)

        case WM_GETMINMAXINFO:
            if minSize != nil || maxSize != nil {
                let info = UnsafeMutablePointer<MINMAXINFO>(bitPattern: UInt(lparam))
                if let info {
                    if let mn = minSize {
                        info.pointee.ptMinTrackSize.x = Int32(mn.width)
                        info.pointee.ptMinTrackSize.y = Int32(mn.height)
                    }
                    if let mx = maxSize {
                        info.pointee.ptMaxTrackSize.x = Int32(mx.width)
                        info.pointee.ptMaxTrackSize.y = Int32(mx.height)
                    }
                    return 0
                }
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam)

        case WM_COMMAND:
            // WPARAM 상위 워드는 알림 코드, 하위 워드는 메뉴 ID
            // (메뉴 항목은 0, 가속기는 1).
            let id = UInt32(wparam & 0xFFFF)
            let entry = KSWin32MenuRegistry.shared.resolve(id: id)
            if let cmd = entry.command {
                KSWindowsCommandRouter.shared.dispatch(
                    command: cmd, itemID: entry.itemID)
                return 0
            }
            return DefWindowProcW(hwnd, msg, wparam, lparam)

        case WM_DESTROY:
            if let hwnd {
                Win32App.shared.unregister(hwnd: hwnd)
                KSWin32HandleRegistry.shared.unregister(label: label)
                KSWin32MainWindowTracker.shared.untrack(hwnd: hwnd)
            }
            webviewHost?.dispose()
            webviewHost = nil
            if let brush = backgroundBrush {
                _ = DeleteObject(brush)
                backgroundBrush = nil
            }
            hwnd = nil
            // 데모용 종료 메시지. 실제 PAL은 윈도우 수를 추적해 마지막
            // 윈도우가 닫힐 때만 종료한다.
            PostQuitMessage(0)
            return 0

        default:
            return DefWindowProcW(hwnd, msg, wparam, lparam)
        }
    }
}
#endif
