#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore

    /// Process-wide Win32 application state: module handle, registered window
    /// class, and the message pump.
    ///
    /// All interaction with the window system happens on the main thread, so
    /// this type is `@MainActor`-isolated.
    @MainActor
    internal final class Win32App {
        static let shared = Win32App()

        private let log = KSLog.logger("platform.windows.app")
        private(set) var instanceHandle: HINSTANCE
        private(set) var classAtom: ATOM = 0
        private var comInitialized: Bool = false
        private var jobObject: HANDLE?

        /// Maps HWND (as UInt bit pattern) to the Swift `Win32Window` that owns
        /// it so that the shared `WNDPROC` can route messages. We key on UInt
        /// rather than `UnsafeMutableRawPointer` because only `Sendable` values
        /// may cross the `@convention(c) → @MainActor` boundary under Swift 6
        /// strict concurrency.
        fileprivate var windows: [UInt: Win32Window] = [:]

        /// Optional WM_HOTKEY router. Set by the accelerator backend so that
        /// hot-key messages received by the message pump can be dispatched
        /// to registered handlers. The handler is invoked on the main thread.
        var hotKeyHandler: ((Int32) -> Void)?

        /// Main / UI thread id captured as early as possible (at
        /// `ensureCOMInitialized` and again at `runMessageLoop`). The shared
        /// `WNDPROC` consults this from the `@convention(c)` thunk — which
        /// has no actor isolation of its own — to decide whether it is safe
        /// to enter `MainActor.assumeIsolated`. A `0` value means the main
        /// thread is not yet known and the WNDPROC will conservatively
        /// proceed (this only happens before COM init, when no live HWND
        /// exists yet).
        nonisolated(unsafe) static var mainThreadID: DWORD = 0

        private init() {
            // GetModuleHandleW(nil)은 자기 프로세스 모듈의 HINSTANCE를
            // 반환한다. Win32 계약상 호스트 프로세스 컨텍스트에서는 절대
            // NULL을 반환하지 않으므로 이는 회복 불가능한 호스트 환경
            // 손상에 해당한다. 우회로가 없는 부트스트랩 단계라 `precondition`
            // 으로 명시적으로 중단한다(원래 `!`와 의미 동일하되 진단 메시지
            // 가 분명하다).
            guard let handle = GetModuleHandleW(nil) else {
                preconditionFailure(
                    "GetModuleHandleW(nil) returned NULL — host process is in an unsupported state")
            }
            self.instanceHandle = handle
        }

        /// Initializes the main-thread COM apartment as STA (single-threaded
        /// apartment). WebView2 requires the UI thread to be STA — failing to
        /// initialize returns `RPC_E_CHANGED_MODE` (0x80010106) from
        /// `CreateCoreWebView2Environment`.
        ///
        /// On Windows, the Swift / Foundation runtime may have already
        /// initialized the thread as MTA before `main()` runs. In that case
        /// `CoInitializeEx(STA)` returns `RPC_E_CHANGED_MODE` and leaves the
        /// thread in MTA. We work around this by calling `CoUninitialize()`
        /// once to cancel that prior init, then requesting STA. This is safe
        /// because the UI thread never actually needs MTA semantics here.
        func ensureCOMInitialized() throws(KSError) {
            guard !comInitialized else { return }

            // Capture main thread id for WNDPROC routing.
            if Win32App.mainThreadID == 0 {
                Win32App.mainThreadID = GetCurrentThreadId()
            }

            let flags = DWORD(COINIT_APARTMENTTHREADED.rawValue) | DWORD(COINIT_DISABLE_OLE1DDE.rawValue)

            var hr = CoInitializeEx(nil, flags)
            let rpcEChangedMode: Int32 = Int32(bitPattern: 0x8001_0106)

            if hr == rpcEChangedMode {
                log.info("COM already initialized as MTA; re-initializing as STA")
                // 이전(런타임)의 CoInitializeEx를 균형맞춰 모드를 바꿀 수 있게 한다.
                CoUninitialize()
                hr = CoInitializeEx(nil, flags)
            }

            if hr < 0 {
                throw KSError(
                    code: .platformInitFailed,
                    message: "CoInitializeEx failed (HRESULT=0x\(String(UInt32(bitPattern: hr), radix: 16)))")
            }
            comInitialized = true
            log.info("COM initialized (STA, hr=0x\(String(UInt32(bitPattern: hr), radix: 16)))")
        }

        /// 현재 프로세스를 Job Object 에 attach 하여, 호스트 프로세스가
        /// 종료될 때 자식 프로세스(특히 WebView2 의 `msedgewebview2.exe`
        /// 브라우저/렌더러/GPU 헬퍼) 가 함께 종료되도록 한다.
        ///
        /// `ExitProcess` 또는 비정상 종료 시 dispose 경로가 제대로 실행
        /// 되지 못하면 헬퍼 프로세스가 고아(orphan)가 되어 사용자 데이터
        /// 폴더(`*\WebView2`)를 락으로 잡고 있을 수 있다. Job Object 의
        /// `KILL_ON_JOB_CLOSE` 가 OS 레벨 안전망 역할을 한다.
        ///
        /// Idempotent. 실패는 치명적이지 않으므로 경고만 남긴다.
        func ensureProcessJobObject() {
            guard jobObject == nil else { return }

            guard let job = CreateJobObjectW(nil, nil) else {
                log.warning(
                    "CreateJobObjectW failed (GetLastError=\(GetLastError())); WebView2 helpers may not be cleaned up on abrupt exit"
                )
                return
            }

            var info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
            info.BasicLimitInformation.LimitFlags =
                DWORD(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
            let infoSize = DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size)
            let setOK = withUnsafeMutablePointer(to: &info) { ptr -> Bool in
                SetInformationJobObject(
                    job,
                    JobObjectExtendedLimitInformation,
                    ptr,
                    infoSize)
            }
            if !setOK {
                log.warning(
                    "SetInformationJobObject failed (GetLastError=\(GetLastError())); closing job handle"
                )
                _ = CloseHandle(job)
                return
            }

            if !AssignProcessToJobObject(job, GetCurrentProcess()) {
                // ERROR_ACCESS_DENIED (5): 이미 다른 잡(예: 디버거/컨테이너)에
                // 속한 경우. Win8+ 는 nested job 을 허용하지만 거부될 수 있다.
                log.warning(
                    "AssignProcessToJobObject failed (GetLastError=\(GetLastError())); WebView2 helpers may survive abrupt exit"
                )
                _ = CloseHandle(job)
                return
            }

            jobObject = job
            log.info("Process attached to JobObject (KILL_ON_JOB_CLOSE)")
        }

        /// Registers the shared window class. Idempotent.
        func ensureWindowClassRegistered() throws(KSError) {
            guard classAtom == 0 else { return }

            let className = "KalsaeWindow"
            let atom = className.withUTF16Pointer { namePtr -> ATOM in
                var wc = WNDCLASSEXW()
                wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
                wc.style = UINT(CS_HREDRAW | CS_VREDRAW)
                wc.lpfnWndProc = { hwnd, msg, wparam, lparam in
                    Win32App.dispatch(hwnd, msg, wparam, lparam)
                }
                wc.hInstance = self.instanceHandle
                wc.hCursor = LoadCursorW(nil, loadCursorIdcArrow)
                wc.hbrBackground = HBRUSH(bitPattern: UInt(COLOR_WINDOW + 1))
                wc.lpszClassName = namePtr
                return RegisterClassExW(&wc)
            }
            guard atom != 0 else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "RegisterClassExW failed (GetLastError=\(GetLastError()))")
            }
            classAtom = atom
            log.info("Registered window class 'KalsaeWindow' (atom=\(atom))")
        }

        func register(_ window: Win32Window) {
            guard let hwnd = window.hwnd else { return }
            windows[Self.key(for: hwnd)] = window
        }

        func unregister(hwnd: HWND) {
            windows.removeValue(forKey: Self.key(for: hwnd))
        }

        /// Looks up the tracked `Win32Window` for an HWND. Used by the
        /// `KSWindowsWindowBackend` PAL implementation to act on the window
        /// referenced by a `KSWindowHandle`.
        func window(for hwnd: HWND) -> Win32Window? {
            windows[Self.key(for: hwnd)]
        }

        /// All currently-tracked `Win32Window` instances. Order is unspecified.
        func allWindows() -> [Win32Window] {
            Array(windows.values)
        }

        static func key(for hwnd: HWND) -> UInt {
            UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))
        }

        /// Runs the classic Win32 message loop. Returns the exit code supplied
        /// to `PostQuitMessage`.
        func runMessageLoop() -> Int32 {
            Win32App.mainThreadID = GetCurrentThreadId()
            var msg = MSG()
            // Swift WinSDK 오버레이는 GetMessageW를 Bool 반환으로 가져와
            // 드물게 발생하는 -1 에러 케이스를 `false`(WM_QUIT과 동일)로
            // 단읽한다. 이 점을 수용한다.
            while GetMessageW(&msg, nil, 0, 0) {
                if msg.message == UINT(WM_HOTKEY) {
                    hotKeyHandler?(Int32(msg.wParam))
                }
                _ = TranslateMessage(&msg)
                _ = DispatchMessageW(&msg)
            }
            return Int32(msg.wParam)
        }

        // MARK: - Shared WNDPROC

        /// `@convention(c)` entry point. Finds the target `Win32Window` and
        /// forwards the message to it.
        ///
        /// Windows normally delivers messages to the thread that owns the HWND
        /// (the main / UI thread for our windows), but a small number of
        /// system / inter-thread messages — most notably `WM_NCACTIVATE` and
        /// `WM_ACTIVATE` triggered by focus changes into the embedded
        /// WebView2 child HWND — can be dispatched synchronously from a
        /// worker thread (msedgewebview2's UI/focus thread, COM marshaller,
        /// etc.). Entering `MainActor.assumeIsolated` from such a thread
        /// would trip libdispatch's queue assertion and crash the host with
        /// exit code `0xC000041D` (STATUS_FATAL_USER_CALLBACK_EXCEPTION).
        ///
        /// We therefore route messages through the per-instance handler only
        /// when we are actually on the captured main thread.
        ///
        /// Off-main thread invocations are split:
        ///
        /// 1) Lifecycle messages (`WM_CLOSE` / `WM_DESTROY` / `WM_NCDESTROY`)
        ///    MUST NOT be silently delegated to `DefWindowProcW` from the
        ///    wrong thread — `WM_CLOSE` would skip our close interceptors
        ///    (`hideOnClose`, `closeInterceptEnabled`, `onBeforeCloseSwift`)
        ///    and `WM_DESTROY` would never reach our handler that posts
        ///    `WM_QUIT`, hanging the main message pump forever. Instead we
        ///    `PostMessageW` them so they re-enter the owning (main) thread's
        ///    queue and our normal handler runs.
        ///
        /// 2) Everything else (activation, focus, paint hints, cross-process
        ///    WebView2 notifications) is forwarded to `DefWindowProcW`, which
        ///    is documented as safe to call from any thread. The
        ///    corresponding `__ks.window.focus`/`.blur` events may be missed
        ///    when activation crosses the WebView2 process boundary, but the
        ///    window itself remains fully functional.
        private static let dispatch:
            @convention(c) (
                HWND?, UINT, WPARAM, LPARAM
            ) -> LRESULT = { hwnd, msg, wparam, lparam in
                guard let hwnd else {
                    return DefWindowProcW(nil, msg, wparam, lparam)
                }
                let mainTID = Win32App.mainThreadID
                if mainTID != 0 && GetCurrentThreadId() != mainTID {
                    switch Int32(msg) {
                    case WM_CLOSE, WM_DESTROY, WM_NCDESTROY:
                        // Re-queue to the owning (main) thread so our
                        // normal handler runs and `PostQuitMessage` fires.
                        _ = PostMessageW(hwnd, msg, wparam, lparam)
                        return 0
                    default:
                        return DefWindowProcW(hwnd, msg, wparam, lparam)
                    }
                }
                let key = Win32App.key(for: hwnd)
                let handled: LRESULT? = MainActor.assumeIsolated {
                    if let window = Win32App.shared.windows[key] {
                        return window.handle(msg: msg, wparam: wparam, lparam: lparam)
                    }
                    return nil
                }
                return handled ?? DefWindowProcW(hwnd, msg, wparam, lparam)
            }
    }

    // Windows 용 Swift는 IDC_ARROW를 Swift 심볼로 불러오지 않는다(정수를
    // LPWSTR로 캐스팅하는 매크로만). 여기서 재현한다.
    private var loadCursorIdcArrow: UnsafePointer<WCHAR>? {
        UnsafePointer<WCHAR>(bitPattern: 32512)
    }
#endif
