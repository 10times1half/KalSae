#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore

    // MARK: - KSWindowsTrayBackend + message-only 윈도우

    // 이 확장은 트레이 아이콘 콜백을 받기 위한 message-only 윈도우의
    // 클래스 등록(WNDCLASSEXW / RegisterClassExW), `WM_USER+20` /
    // `WM_COMMAND` 라우팅, 그리고 우클릭 컨텍스트 메뉴 표시 로직을
    // 모은다.
    //
    // 메인 파일(`KSWindowsTrayBackend.swift`)은 `Shell_NotifyIconW`의
    // NIM_ADD/NIM_MODIFY/NIM_DELETE 등 백엔드 표면 메서드와 정적 상태
    // 관리에 집중하고, message-only 윈도우의 생명주기와 메시지 처리는
    // 이 파일이 담당한다.

    extension KSWindowsTrayBackend {

        /// message-only 윈도우(`HWND_MESSAGE`)를 생성한다.
        ///
        /// `HWND_MESSAGE`(값 -3)를 parent로 전달하면 가시 윈도우 계층에
        /// 속하지 않는 message-only 윈도우가 생성된다. 이 윈도우는:
        /// 1. 작업 표시줄에 나타나지 않음
        /// 2. 포커스를 받지 않음
        /// 3. Z-순서에 영향을 주지 않음
        /// 4. 오직 `PeekMessage`/`GetMessage`로만 메시지를 수신
        ///
        /// 트레이 아이콘의 `NOTIFYICONDATAW.hWnd`로 이 윈도우를 지정하면,
        /// `Shell_NotifyIconW`가 발생시키는 콜백(`uCallbackMessage`으로
        /// 지정된 사용자 정의 메시지)이 이 윈도우의 WNDPROC로 전달된다.
        ///
        /// 윈도우 생성이 끝나면 정적 변수 `trayWindowHWND`와 `activeBackend`
        /// 를 설정하여 WNDPROC가 이 백엔드 인스턴스를 찾을 수 있도록 한다.
        internal func ensureMessageWindow() throws(KSError) {
            guard messageWindow == nil else { return }

            try Self.registerMessageWindowClass()

            let className = Self.messageWindowClass
            let titlePtr: UnsafePointer<UInt16>? = nil

            let hwnd = className.withUTF16Pointer { cls -> HWND? in
                CreateWindowExW(
                    0,  // 확장 스타일 (없음)
                    cls,  // 등록된 윈도우 클래스 이름
                    titlePtr,  // 윈도우 제목 (없음)
                    0,  // 윈도우 스타일 (message-only는 0)
                    0, 0, 0, 0,  // 위치/크기 (의미 없음)
                    HWND(bitPattern: -3),  // HWND_MESSAGE — message-only parent
                    nil,  // 메뉴 핸들
                    Win32App.shared.instanceHandle,  // 인스턴스 핸들
                    nil)  // 생성 매개변수
            }
            guard let hwnd else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "Failed to create tray message window")
            }
            messageWindow = hwnd
            // 정적 변수에 HWND를 UInt로 저장 — WNDPROC는 클로저 캡처 없이
            // 이 값을 확인해 올바른 백엔드 윈도우인지 판단한다.
            Self.trayWindowHWND = UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))
            Self.activeBackend = self
        }

        /// 윈도우 클래스 "KalsaeTray"를 등록한다 (최초 1회).
        ///
        /// `WNDCLASSEXW.lpfnWndProc`에 설정된 WNDPROC에서 다음을 처리한다:
        ///
        /// **스레드 안전 가드:**
        /// - WNDPROC는 메시지를 보낸 스레드의 컨텍스트에서 실행된다.
        ///   대부분의 메시지는 message-only 윈도우를 소유한 전용 Win32
        ///   UI 스레드에서 도착하지만, 시스템/COM 브로드캐스트 메시지가
        ///   다른 스레드에서 `SendMessageW`로 동기 디스패치될 수 있다.
        /// - 그런 경우 `Win32App.unsafelyAssumeMainActor`가
        ///   `dispatch_assert_queue` precondition을 트립하므로,
        ///   `GetCurrentThreadId()` != `mainThreadID`면 즉시
        ///   `DefWindowProcW`로 폴백한다.
        ///
        /// **생명주기 메시지 재전송:**
        /// - `WM_CLOSE`/`WM_DESTROY`/`WM_NCDESTROY`는 `DefWindowProcW`
        ///   호출 시 윈도우를 즉시 파괴하므로, 우리의 `_removeOnMain()`
        ///   정리 경로(`Shell_NotifyIconW(NIM_DELETE)`)를 우회한다.
        /// - 이 메시지들은 `PostMessageW`로 메인 스레드 메시지 큐에
        ///   다시 넣어(재전송) 정리 기회를 보장한다.
        ///
        /// **트레이 메시지 라우팅:**
        /// - 현재 HWND가 `trayWindowHWND`와 일치하면 `handleTrayMessage()`
        ///   에게 메시지 처리를 위임한다.
        internal static func registerMessageWindowClass() throws(KSError) {
            guard !registeredClass else { return }
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.lpfnWndProc = { hwnd, msg, wp, lp in
                // Win32 계약상 WNDPROC 호출 시 `hwnd`는 항상 유효하지만,
                // Swift에서는 Optional로 표현되므로 명시적으로 가드한다.
                guard let hwnd else { return DefWindowProcW(hwnd, msg, wp, lp) }
                // WNDPROC가 비-메인 스레드에서 호출되면
                // `Win32App.unsafelyAssumeMainActor`가 libdispatch
                // precondition을 트립한다
                // (`STATUS_FATAL_USER_CALLBACK_EXCEPTION`).
                // 메시지 윈도우는 메인 스레드가 소유하지만 시스템 또는
                // COM 브로드캐스트가 다른 스레드에서 동기 디스패치할 수
                // 있으므로, 보수적으로 스레드 ID를 확인한다.
                //
                // 생명주기 메시지(`WM_CLOSE`/`WM_DESTROY`/`WM_NCDESTROY`)
                // 는 `DefWindowProcW` 폴백 시 윈도우를 즉시 파괴해 우리
                // 정리 경로를 우회시키므로 `PostMessageW`로 메인 스레드
                // 큐에 재전송한다.
                let mainTID = Win32App.mainThreadID
                if mainTID != 0 && GetCurrentThreadId() != mainTID {
                    switch Int32(msg) {
                    case WM_CLOSE, WM_DESTROY, WM_NCDESTROY:
                        _ = PostMessageW(hwnd, msg, wp, lp)
                        return 0
                    default:
                        return DefWindowProcW(hwnd, msg, wp, lp)
                    }
                }
                if UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))
                    == KSWindowsTrayBackend.trayWindowHWND
                {
                    let handled: Bool = Win32App.unsafelyAssumeMainActor {
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

        /// message-only 윈도우가 수신한 트레이 메시지를 처리한다.
        ///
        /// **트레이 콜백 메시지 (`WM_USER + 20`):**
        /// `Shell_NotifyIconW`가 트레이 아이콘에서 마우스/키보드 이벤트가
        /// 발생할 때 이 메시지를 `uCallbackMessage`으로 전송한다.
        /// 이 메시지는 `lparam` 하위 16비트에 실제 Win32 메시지
        /// (예: `WM_LBUTTONUP`, `WM_RBUTTONUP`, `WM_CONTEXTMENU`)를
        /// 전달한다.
        ///
        /// - `WM_LBUTTONUP`: 왼쪽 버튼 클릭 → `onLeftClickCommand` 실행
        /// - `WM_RBUTTONUP`/`WM_CONTEXTMENU`: 우클릭 → `showTrayMenu()`
        ///
        /// **WM_COMMAND:**
        /// `TrackPopupMenu`로 표시된 컨텍스트 메뉴에서 항목이 선택되면
        /// WM_COMMAND가 메뉴 소유자 윈도우(message-only 윈도우)로 전송된다.
        /// `wparam` 하위 16비트에 메뉴 항목 ID가 포함되어 있으며,
        /// `KSWin32MenuRegistry`에서 해당 ID의 command와 itemID를 조회하여
        /// `KSWindowsCommandRouter`로 디스패치한다.
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
                let log = KSLog.logger("platform.windows.tray")
                let entry = KSWin32MenuRegistry.shared.resolve(id: id)
                log.debug("WM_COMMAND id=\(id) command=\(entry.command ?? "<nil>") itemID=\(entry.itemID ?? "<nil>")")
                if let cmd = entry.command {
                    KSWindowsCommandRouter.shared.dispatch(command: cmd, itemID: entry.itemID)
                    log.debug("WM_COMMAND dispatched command=\(cmd)")
                } else {
                    log.warning("WM_COMMAND id=\(id) had no registered command")
                }
                return true
            }
            return false
        }

        /// 현재 커서 위치에 우클릭 컨텍스트 메뉴를 표시한다.
        ///
        /// 동작 순서:
        /// 1. `KSWindowsMenuBackend.buildMenu(items, isPopup: true)`로
        ///    `currentMenuItems`를 `HMENU`로 변환
        /// 2. `GetCursorPos`로 현재 마우스 위치 획득
        /// 3. `SetForegroundWindow(messageWindow)` — 키보드로 메뉴를
        ///    조작할 때 Win32가 올바르게 동작하기 위해 필요 (MS 문서 필수)
        /// 4. `TrackPopupMenu(TPM_RIGHTBUTTON | TPM_LEFTALIGN | TPM_BOTTOMALIGN,
        ///    pt.x, pt.y, 0, messageWindow, nil)` — 메뉴 표시
        /// 5. `PostMessageW(messageWindow, WM_NULL)` — 메뉴가 닫힌 후
        ///    메시지 큐를 깨끗이 정리 (Win32 관용구)
        internal func showTrayMenu() {
            guard !currentMenuItems.isEmpty else { return }
            guard let messageWindow else { return }

            // 트레이 메뉴는 클릭이 WM_COMMAND으로 전달되도록 popup
            // HMENU(CreatePopupMenu로 생성)에서 시작되어야 한다.
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
            // Microsoft 문서에 따라 키보드로 메뉴를 열 때
            // `SetForegroundWindow`가 필수이다.
            _ = SetForegroundWindow(messageWindow)
            _ = TrackPopupMenu(
                menu,
                UINT(TPM_RIGHTBUTTON | TPM_LEFTALIGN | TPM_BOTTOMALIGN),
                pt.x, pt.y,
                0, messageWindow, nil)
            // 메뉴를 깔끔하게 닫기 위해 필요하다. (Win32의 구식 특이 사항.)
            _ = PostMessageW(messageWindow, UINT(WM_NULL), 0, 0)
        }
    }
#endif
