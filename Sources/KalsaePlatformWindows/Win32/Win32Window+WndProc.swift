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
            return 0

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
