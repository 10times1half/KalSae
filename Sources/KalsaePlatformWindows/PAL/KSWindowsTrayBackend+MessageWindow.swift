#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore

    // MARK: - KSWindowsTrayBackend hidden message window
    //
    // 트레이 아이콘 콜백을 받기 위한 message-only 윈도우 클래스 등록과
    // `WM_USER+20` / `WM_COMMAND` 라우팅, 우클릭 컨텍스트 메뉴 표시
    // 로직을 모은 확장. 메인 파일은 `Shell_NotifyIconW` 인스톨/모디파이/
    // 디스폴 등 백엔드 표면 메서드와 정적 상태에 집중한다.

    extension KSWindowsTrayBackend {

        internal func ensureMessageWindow() throws(KSError) {
            guard messageWindow == nil else { return }

            try Self.registerMessageWindowClass()

            let className = Self.messageWindowClass
            let titlePtr: UnsafePointer<UInt16>? = nil

            let hwnd = className.withUTF16Pointer { cls -> HWND? in
                CreateWindowExW(
                    0, cls, titlePtr,
                    0,
                    0, 0, 0, 0,
                    HWND(bitPattern: -3),  // HWND_MESSAGE
                    nil, Win32App.shared.instanceHandle, nil)
            }
            guard let hwnd else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "Failed to create tray message window")
            }
            messageWindow = hwnd
            Self.trayWindowHWND = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))
            Self.activeBackend = self
        }

        internal static func registerMessageWindowClass() throws(KSError) {
            guard !registeredClass else { return }
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.lpfnWndProc = { hwnd, msg, wp, lp in
                // Win32 계약상 WNDPROC 호출 시 `hwnd`는 항상 유효하지만,
                // Swift에서는 Optional로 표현되므로 명시적으로 가드한다.
                guard let hwnd else { return DefWindowProcW(hwnd, msg, wp, lp) }
                if UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))
                    == KSWindowsTrayBackend.trayWindowHWND
                {
                    let handled: Bool = MainActor.assumeIsolated {
                        guard let backend = KSWindowsTrayBackend.activeBackend else {
                            return false
                        }
                        return backend.handleTrayMessage(msg: msg, wparam: wp, lparam: lp)
                    }
                    if handled { return 0 }
                }
                return DefWindowProcW(hwnd, msg, wp, lp)
            }
            wc.hInstance = Win32App.shared.instanceHandle
            let atom = messageWindowClass.withUTF16Pointer { ptr -> ATOM in
                wc.lpszClassName = ptr
                return RegisterClassExW(&wc)
            }
            guard atom != 0 else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "Tray RegisterClassExW failed (GLE=\(GetLastError()))")
            }
            registeredClass = true
        }

        internal func handleTrayMessage(msg: UINT, wparam: WPARAM, lparam: LPARAM) -> Bool {
            if msg == Self.trayCallbackMessage {
                let event = UINT(lparam & 0xFFFF)
                switch Int32(event) {
                case WM_LBUTTONUP:
                    if let cmd = onLeftClickCommand {
                        KSWindowsCommandRouter.shared.dispatch(command: cmd, itemID: nil)
                    }
                case WM_RBUTTONUP, WM_CONTEXTMENU:
                    showTrayMenu()
                default:
                    break
                }
                return true
            }
            if Int32(msg) == WM_COMMAND {
                let id = UInt32(wparam & 0xFFFF)
                let entry = KSWin32MenuRegistry.shared.resolve(id: id)
                if let cmd = entry.command {
                    KSWindowsCommandRouter.shared.dispatch(command: cmd, itemID: entry.itemID)
                }
                return true
            }
            return false
        }

        internal func showTrayMenu() {
            guard !currentMenuItems.isEmpty else { return }
            guard let messageWindow else { return }

            // 트레이 메뉴는 클릭이 WM_COMMAND으로 전달되도록 non-popup HMENU
            // 루트(CreatePopupMenu로 생성)에서 나와야 한다.
            let menu: HMENU
            do {
                menu = try KSWindowsMenuBackend.buildMenu(
                    currentMenuItems, isPopup: true)
            } catch {
                return
            }
            defer { DestroyMenu(menu) }

            var pt = POINT()
            _ = GetCursorPos(&pt)
            // Microsoft 문서에 따라 키보드 구동 메뉴에는 필수.
            _ = SetForegroundWindow(messageWindow)
            _ = TrackPopupMenu(
                menu,
                UINT(TPM_RIGHTBUTTON | TPM_LEFTALIGN | TPM_BOTTOMALIGN),
                pt.x, pt.y,
                0, messageWindow, nil)
            // 메뉴를 깔끔하게 닫기 위해 필요하다. (Win32 구식 특이 사항.)
            _ = PostMessageW(messageWindow, UINT(WM_NULL), 0, 0)
        }
    }
#endif
