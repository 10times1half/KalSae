#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore
    internal import Foundation

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

        /// WNDPROC 가 UI 스레드(non-MainActor)에서 안전하게 윈도우를
        /// 찾기 위한 nonisolated 미러. `register` / `unregister` 가
        /// `windows` 와 함께 갱신한다. NSLock 으로 보호.
        nonisolated(unsafe) fileprivate static var windowsMirror: [UInt: Win32Window] = [:]
        nonisolated(unsafe) fileprivate static let windowsMirrorLock = NSLock()

        nonisolated static func lookupWindowNonisolated(key: UInt) -> Win32Window? {
            windowsMirrorLock.lock()
            defer { windowsMirrorLock.unlock() }
            return windowsMirror[key]
        }

        /// Optional WM_HOTKEY router. Set by the accelerator backend so that
        /// hot-key messages received by the message pump can be dispatched
        /// to registered handlers. The handler is invoked on the main thread.
        ///
        /// 데디케이트 UI 스레드 도입 후: UI 스레드의 메시지 펌프는
        /// `hotKeyHandlerNonisolated` 미러를 읽어 호출한다. 두 값은 항상
        /// 동시에 갱신되어야 한다.
        var hotKeyHandler: ((Int32) -> Void)? {
            didSet {
                Win32App.hotKeyHandlerNonisolated = hotKeyHandler
            }
        }

        /// UI 스레드 펌프(`Win32App+UIThread.swift`)가 참조하는 nonisolated
        /// 미러. `hotKeyHandler` 설정 시 자동 갱신된다. 호출 대상은
        /// MainActor 격리 클로저이지만, 호출 함수가 즉시 Swift main 큐로
        /// 디스패치하기만 한다는 contract 하에 nonisolated 컨텍스트에서
        /// 호출해도 안전하다.
        nonisolated(unsafe) static var hotKeyHandlerNonisolated: ((Int32) -> Void)?

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
            let k = Self.key(for: hwnd)
            windows[k] = window
            Self.windowsMirrorLock.lock()
            Self.windowsMirror[k] = window
            Self.windowsMirrorLock.unlock()
        }

        func unregister(hwnd: HWND) {
            let k = Self.key(for: hwnd)
            windows.removeValue(forKey: k)
            Self.windowsMirrorLock.lock()
            Self.windowsMirror.removeValue(forKey: k)
            Self.windowsMirrorLock.unlock()
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

        /// 메인 진입점. 전용 UI 스레드를 보장하고, Swift main 스레드는
        /// UI 스레드 종료까지 블로킹한다. 종료 코드는 `PostQuitMessage`
        /// 로 전달된 값을 그대로 반환한다.
        ///
        /// 과거에는 이 함수가 직접 `GetMessageW` 루프를 돌았지만, Swift
        /// `@MainActor` 가 Windows 에서 단일 OS 스레드에 고정되지 않아
        /// `CreateWindowExW` 호출 스레드와 펌프 스레드가 갈리는 문제가
        /// 있었다. 자세한 배경은 `Win32App+UIThread.swift` 헤더 주석 참고.
        func runMessageLoop() -> Int32 {
            do {
                try Win32App.ensureUIThread()
            } catch {
                log.error("ensureUIThread failed: \(error.message)")
                return Int32(bitPattern: 0xFFFF_FFFF)
            }
            return Win32App.waitForUIThreadExit()
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
                // WNDPROC 는 전용 UI 스레드(Win32App+UIThread.swift)에서
                // 호출된다. 이 스레드는 Swift 의 MainActor 가 아니므로
                // `MainActor.assumeIsolated` 는 트랩한다. 대신 nonisolated
                // 미러(`Win32App.windowsMirror`)에서 윈도우를 찾아 `handle`
                // 을 unsafe 캐스트로 직접 호출한다. 안전성: Win32Window 의
                // 가변 상태는 (a) UI 스레드 WNDPROC, (b) `runOnUIThread`
                // 마샬링 클로저, (c) postJob 메시지 → 모두 UI 스레드에서만
                // 단일 진입한다.
                guard let window = Win32App.lookupWindowNonisolated(key: key) else {
                    return DefWindowProcW(hwnd, msg, wparam, lparam)
                }
                typealias HandleFn = (UINT, WPARAM, LPARAM) -> LRESULT
                let mainIsolated: @MainActor (UINT, WPARAM, LPARAM) -> LRESULT = window.handle
                let nonIsolated = unsafeBitCast(mainIsolated, to: HandleFn.self)
                return nonIsolated(msg, wparam, lparam)
            }
    }

    // Windows 용 Swift는 IDC_ARROW를 Swift 심볼로 불러오지 않는다(정수를
    // LPWSTR로 캐스팅하는 매크로만). 여기서 재현한다.
    private var loadCursorIdcArrow: UnsafePointer<WCHAR>? {
        UnsafePointer<WCHAR>(bitPattern: 32512)
    }
#endif
