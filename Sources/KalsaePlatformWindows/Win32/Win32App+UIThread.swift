#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore
    internal import Foundation

    // MARK: - Dedicated Win32 UI thread
    //
    // Swift 의 `MainActor` 는 Windows 에서 단일 OS 스레드에 고정되지 않는다.
    // libdispatch 의 main queue 워커는 `await` 경계마다 다른 스레드에서
    // 재개될 수 있어, `CreateWindowExW` 를 호출한 스레드와 `GetMessageW`
    // 루프를 도는 스레드가 달라지는 현상이 실제로 관찰되었다. Win32 에서
    // HWND 는 생성 스레드에 소유되며 그 스레드가 사라지면 OS 가 윈도우를
    // 조용히 파괴한다. 결과적으로 `kalsae dev` (특히 dev-server 모드의
    // React 프리셋) 에서 윈도우가 열리자마자 닫혀버린다.
    //
    // 이 파일은 전용 UI 스레드를 도입해 다음을 보장한다:
    //   1. 모든 `CreateWindowExW` / `DestroyWindow` / WebView2 콘트롤러
    //      초기화가 동일한 OS 스레드에서 실행된다.
    //   2. 그 스레드가 `GetMessageW` 메시지 펌프를 실제로 돌린다.
    //   3. `runMessageLoop()` 는 Swift main 스레드를 `WaitForSingleObject`
    //      로 블로킹하여, UI 스레드 종료까지 프로세스가 살아있게 한다.
    //
    // 다른 스레드(주로 Swift main / @MainActor) 는 `runOnUIThread { ... }`
    // 로 동기 마샬링한다. 내부적으로는 메시지-온리 invoker HWND 에
    // `SendMessageW(WM_KS_UI_INVOKE, ...)` 를 보내고, invoker WNDPROC 이
    // UI 스레드 컨텍스트에서 박스화된 클로저를 실행한다. SendMessageW 는
    // 핸들러가 반환할 때까지 호출자를 블로킹하므로 호출 의미는 동기 함수
    // 와 동일하다.

    extension Win32App {
        /// 사용자-정의 WM 메시지. invoker HWND 가 받아서 박스화된 클로저
        /// 를 실행한다.
        nonisolated static let WM_KS_UI_INVOKE: UINT = UINT(WM_USER) + 200

        /// `KSWindowsDemoHost` 가 `runMessageLoop` 을 호출하기 전에 true 로
        /// 설정한다. true 일 때만 마지막 윈도우 WM_DESTROY 에서
        /// `PostQuitMessage` 를 호출해 UI 스레드를 종료한다. 테스트 대상
        /// 경로 (Win32Window 를 직접 생성/파괴) 에서는 false 로 둡고 UI
        /// 스레드가 프로세스 수명 동안 살아있게 한다.
        nonisolated(unsafe) static var autoQuitOnLastWindow: Bool = false

        nonisolated(unsafe) private static var _uiThreadHandle: HANDLE?
        nonisolated(unsafe) static var uiThreadID: DWORD = 0
        nonisolated(unsafe) private static var invokerHWND: HWND?
        nonisolated(unsafe) private static var uiInitError: KSError?

        nonisolated(unsafe) private static let uiThreadLock = NSLock()
        nonisolated static var _uiThreadLockShared: NSLock { uiThreadLock }
        nonisolated(unsafe) private static var uiReadyEvent: HANDLE?

        /// 첫 호출 시 전용 UI 스레드를 스폰한다. 멱등.
        nonisolated static func ensureUIThread() throws(KSError) {
            uiThreadLock.lock()
            defer { uiThreadLock.unlock() }
            if _uiThreadHandle != nil { return }

            // Manual-reset event 로 "ready" 신호를 받는다. 핸들은 프로세스
            // 생애 동안 유지한다.
            guard let evt = CreateEventW(nil, true, false, nil) else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "CreateEventW failed (GetLastError=\(GetLastError()))")
            }
            uiReadyEvent = evt
            uiInitError = nil

            var tid: UInt32 = 0
            let raw = _beginthreadex(
                nil, 0,
                { _ in
                    Win32App.uiThreadMain()
                    return 0
                },
                nil, 0, &tid)
            guard raw != 0 else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "_beginthreadex failed for UI thread")
            }
            _uiThreadHandle = HANDLE(bitPattern: raw)
            uiThreadID = DWORD(tid)

            _ = WaitForSingleObject(evt, INFINITE)
            if let err = uiInitError {
                _uiThreadHandle = nil
                uiThreadID = 0
                throw err
            }
        }

        /// UI 스레드에서 동기로 `block` 을 실행한다. 이미 UI 스레드에 있으면
        /// 인라인으로 호출한다.
        nonisolated static func runOnUIThread<T>(_ block: () -> T) -> T {
            try? ensureUIThread()
            if GetCurrentThreadId() == uiThreadID {
                return block()
            }
            guard let invoker = invokerHWND else {
                // ensureUIThread 가 성공했는데 invoker 가 nil 이면 호스트
                // 가 손상된 상태 — 폴백으로 인라인 실행.
                return block()
            }
            return withoutActuallyEscaping(block) { escapingBlock in
                let result = _KSUIResultBox<T>()
                let box = _KSUIInvokeBox {
                    result.value = escapingBlock()
                }
                let ptr = Unmanaged.passRetained(box).toOpaque()
                let lp = LPARAM(Int(bitPattern: ptr))
                _ = SendMessageW(invoker, WM_KS_UI_INVOKE, 0, lp)
                // SendMessageW 는 동기이므로 result.value 는 반드시 설정됨.
                guard let v = result.value else {
                    preconditionFailure(
                        "runOnUIThread: SendMessageW returned without setting result")
                }
                return v
            }
        }

        /// Throwing 변종. `block` 이 KSError 를 던지면 호출자에게 전파한다.
        nonisolated static func runOnUIThreadThrowing<T>(
            _ block: () throws(KSError) -> T
        ) throws(KSError) -> T {
            try ensureUIThread()
            if GetCurrentThreadId() == uiThreadID {
                return try block()
            }
            guard let invoker = invokerHWND else {
                return try block()
            }
            let result: Result<T, KSError> = withoutActuallyEscaping(block) { escapingBlock in
                let slot = _KSUIResultBox<Result<T, KSError>>()
                let box = _KSUIInvokeBox {
                    do {
                        let v = try escapingBlock()
                        slot.value = .success(v)
                    } catch let e as KSError {
                        slot.value = .failure(e)
                    } catch {
                        slot.value = .failure(
                            KSError(code: .internal, message: "\(error)"))
                    }
                }
                let ptr = Unmanaged.passRetained(box).toOpaque()
                let lp = LPARAM(Int(bitPattern: ptr))
                _ = SendMessageW(invoker, WM_KS_UI_INVOKE, 0, lp)
                guard let v = slot.value else {
                    preconditionFailure(
                        "runOnUIThreadThrowing: SendMessageW returned without setting result")
                }
                return v
            }
            switch result {
            case .success(let v): return v
            case .failure(let e): throw e
            }
        }

        /// UI 스레드의 종료(WM_QUIT) 를 기다리고 종료 코드를 반환한다.
        nonisolated static func waitForUIThreadExit() -> Int32 {
            guard let h = _uiThreadHandle else { return 0 }
            _ = WaitForSingleObject(h, INFINITE)
            var code: DWORD = 0
            _ = GetExitCodeThread(h, &code)
            return Int32(bitPattern: code)
        }

        // MARK: - UI 스레드 진입점

        private static func uiThreadMain() {
            // 1) STA COM 초기화 — WebView2 가 요구.
            let flags =
                DWORD(COINIT_APARTMENTTHREADED.rawValue)
                | DWORD(COINIT_DISABLE_OLE1DDE.rawValue)
            var hr = CoInitializeEx(nil, flags)
            let rpcEChangedMode: Int32 = Int32(bitPattern: 0x8001_0106)
            if hr == rpcEChangedMode {
                CoUninitialize()
                hr = CoInitializeEx(nil, flags)
            }
            if hr < 0 {
                uiInitError = KSError(
                    code: .platformInitFailed,
                    message:
                        "UI thread CoInitializeEx failed (HRESULT=0x\(String(UInt32(bitPattern: hr), radix: 16)))"
                )
                if let evt = uiReadyEvent { _ = SetEvent(evt) }
                return
            }

            // 2) mainThreadID 를 UI 스레드 ID 로 설정. WNDPROC 의 분기
            //    "현재 스레드 == 메시지를 소유한 스레드" 비교가 이 값을
            //    참고한다.
            Win32App.mainThreadID = GetCurrentThreadId()

            // 3) invoker 윈도우 클래스 등록 + 메시지-온리 윈도우 생성.
            let invokerClass = "KalsaeUIInvoker"
            let hInstance = GetModuleHandleW(nil)
            let registered: ATOM = invokerClass.withUTF16Pointer { namePtr -> ATOM in
                var wc = WNDCLASSEXW()
                wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
                wc.lpfnWndProc = { hwnd, msg, wparam, lparam in
                    if msg == Win32App.WM_KS_UI_INVOKE {
                        if let raw = UnsafeMutableRawPointer(bitPattern: UInt(lparam)) {
                            let box = Unmanaged<_KSUIInvokeBox>.fromOpaque(raw)
                                .takeRetainedValue()
                            box.invoke()
                        }
                        return 0
                    }
                    return DefWindowProcW(hwnd, msg, wparam, lparam)
                }
                wc.hInstance = hInstance
                wc.lpszClassName = namePtr
                return RegisterClassExW(&wc)
            }
            guard registered != 0 else {
                uiInitError = KSError(
                    code: .platformInitFailed,
                    message:
                        "UI thread RegisterClassExW(KalsaeUIInvoker) failed (GetLastError=\(GetLastError()))"
                )
                if let evt = uiReadyEvent { _ = SetEvent(evt) }
                CoUninitialize()
                return
            }

            // HWND_MESSAGE 는 Win32 매크로 `((HWND)-3)` 이지만 Swift overlay 에
            // 노출되지 않는다. 비트패턴으로 재구성한다.
            let HWND_MESSAGE_VALUE: HWND? = HWND(bitPattern: -3)

            let hwnd: HWND? = invokerClass.withUTF16Pointer { cls in
                CreateWindowExW(
                    0, cls, cls, 0,
                    0, 0, 0, 0,
                    HWND_MESSAGE_VALUE,
                    nil, hInstance, nil)
            }
            guard let hwnd else {
                uiInitError = KSError(
                    code: .platformInitFailed,
                    message:
                        "UI thread CreateWindowExW(HWND_MESSAGE) failed (GetLastError=\(GetLastError()))"
                )
                if let evt = uiReadyEvent { _ = SetEvent(evt) }
                CoUninitialize()
                return
            }
            invokerHWND = hwnd

            // 4) ready 신호 — ensureUIThread() 의 WaitForSingleObject 가 깨어남.
            if let evt = uiReadyEvent { _ = SetEvent(evt) }

            // 5) 메시지 펌프. WM_HOTKEY 는 `hotKeyHandlerNonisolated` 가
            //    설정되어 있을 때만 라우팅한다 (accelerator 백엔드가
            //    설치한다). MainActor 격리된 핸들러는 unsafeBitCast 로
            //    nonisolated 함수로 캐스트하여 호출한다 — 호출 대상은
            //    Swift main 으로의 디스패치만 수행한다고 가정.
            var msg = MSG()
            while GetMessageW(&msg, nil, 0, 0) {
                if msg.message == UINT(WM_HOTKEY),
                    let handler = Win32App.hotKeyHandlerNonisolated
                {
                    handler(Int32(msg.wParam))
                }
                _ = TranslateMessage(&msg)
                _ = DispatchMessageW(&msg)
            }

            // 6) 정리 — WM_QUIT 수신 후. invokerHWND 는 의도적으로 파괴하지
            //    않는다 (프로세스 종료 임박).
            CoUninitialize()
        }
    }

    // MARK: - Boxes

    /// Retain 매개체. 클로저 본체를 한 번 실행 후 해제.
    internal final class _KSUIInvokeBox: @unchecked Sendable {
        private let block: () -> Void
        init(_ block: @escaping () -> Void) { self.block = block }
        func invoke() { block() }
    }

    /// 동기 마샬링 결과를 담는 슬롯.
    internal final class _KSUIResultBox<T>: @unchecked Sendable {
        var value: T?
    }
#endif
