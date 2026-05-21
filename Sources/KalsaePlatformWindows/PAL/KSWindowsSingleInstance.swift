#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore
    internal import Logging
    internal import Foundation

    /// Single-instance helper for Windows applications.
    ///
    /// The first process to call `acquire` becomes the **primary**: it owns
    /// a named mutex and a hidden message-only window that receives
    /// `WM_COPYDATA` messages from later launches.
    ///
    /// Subsequent launches detect the existing mutex, locate the primary's
    /// hidden window via `FindWindowExW`, forward their command-line arguments
    /// to it as a UTF-16 `WM_COPYDATA` payload, and exit.
    ///
    /// This is the foundation for "click an .exe, app already running, focus
    /// the existing instance and pass the arg" behaviour familiar from
    /// Wails / Electron.
    public enum KSWindowsSingleInstance {

        public enum Outcome: Sendable {
            /// This process is the primary. Continue normal startup.
            case primary
            /// Another instance is already running; arguments were forwarded.
            /// Caller should exit cleanly.
            case relayed
        }

        /// Attempt to acquire single-instance ownership.
        ///
        /// - Parameters:
        ///   - identifier: Stable application identifier (e.g.
        ///     `"dev.example.MyApp"`). Used to derive the named mutex and
        ///     window class — must be the same across launches.
        ///   - args: The arguments to forward to the primary on relay.
        ///     Defaults to `CommandLine.arguments`.
        ///   - onSecondInstance: Called on the **primary** when a later
        ///     launch forwards arguments to it. Invoked on the main thread.
        /// - Returns: `.primary` if this is the first instance; `.relayed`
        ///   if another instance was found and the arguments were sent.
        @MainActor
        public static func acquire(
            identifier: String,
            args: [String] = CommandLine.arguments,
            onSecondInstance: @escaping @MainActor ([String]) -> Void
        ) -> Outcome {
            let log = KSLog.logger("platform.windows.singleinstance")

            let mutexName = "Local\\Kalsae.\(identifier).mutex"
            let className = "Kalsae.\(identifier).Receiver"

            // 1. 명명된 뮤텍스 생성 시도. 이미 존재하면 프라이머리가 아니다.
            let handle: HANDLE? = mutexName.withUTF16Pointer { CreateMutexW(nil, false, $0) }
            let lastError = GetLastError()
            if handle == nil {
                log.warning("CreateMutexW failed (GetLastError=\(lastError)); proceeding as primary anyway")
                return installPrimaryReceiver(
                    className: className,
                    onSecondInstance: onSecondInstance,
                    log: log)
            }

            if Int32(lastError) == ERROR_ALREADY_EXISTS {
                // 프라이머리가 아닌 경우. 인자를 전달하고 반환한다.
                relayArguments(args: args, className: className, log: log)
                // 소유권 없는 핸들을 해제한다.
                CloseHandle(handle)
                return .relayed
            }

            // 뮤텍스를 소유한 경우 — 수신기를 설치한다.
            // 참고: 프로세스 수명 동안 의도적으로 뮤텍스 핸들을 누수한다.
            // 닫으면 단일 인스턴스 지위를 잃는다.
            return installPrimaryReceiver(
                className: className,
                onSecondInstance: onSecondInstance,
                log: log)
        }

        // MARK: - Primary path

        /// Holds the per-process callback for `WM_COPYDATA`. There is at most
        /// one primary instance, so a single static slot is sufficient.
        nonisolated(unsafe) private static var copyDataHandler: (@MainActor ([String]) -> Void)?

        @MainActor
        private static func installPrimaryReceiver(
            className: String,
            onSecondInstance: @escaping @MainActor ([String]) -> Void,
            log: Logger
        ) -> Outcome {
            copyDataHandler = onSecondInstance

            guard let instance = GetModuleHandleW(nil) else {
                log.warning("GetModuleHandleW(nil) returned NULL; single-instance relay disabled")
                return .primary
            }

            // 수신 윈도우는 메시지 펌프가 도는 스레드에 살아야 한다.
            // 부팅 후 Swift main thread는 `WaitForSingleObject(uiThread)`로
            // 영구 blocked되므로 거기서 만들면 WM_COPYDATA가 영원히 처리되지
            // 않는다. 전용 Win32 UI 스레드(`Win32App.ensureUIThread`)에서
            // 클래스 등록과 윈도우 생성을 모두 수행한다.
            do {
                try Win32App.ensureUIThread()
            } catch {
                log.warning("ensureUIThread failed (\(error)); single-instance relay disabled")
                return .primary
            }

            let atom: ATOM = Win32App.runOnUIThread {
                className.withUTF16Pointer { namePtr -> ATOM in
                    var wc = WNDCLASSEXW()
                    wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
                    wc.lpfnWndProc = { hwnd, msg, wparam, lparam in
                        Self.receiverWndProc(hwnd, msg, wparam, lparam)
                    }
                    wc.hInstance = instance
                    wc.lpszClassName = namePtr
                    return RegisterClassExW(&wc)
                }
            }
            guard atom != 0 else {
                log.warning(
                    "RegisterClassExW failed for receiver class (GetLastError=\(GetLastError())); single-instance relay disabled"
                )
                return .primary
            }

            // HWND_MESSAGE = -3. 사용자에게 보이지 않으면서 WM_COPYDATA를
            // 받을 수 있는 메시지 전용 윈도우를 UI 스레드에서 생성한다.
            let hwndMessage = HWND(bitPattern: -3)
            let hwnd: HWND? = Win32App.runOnUIThread {
                className.withUTF16Pointer { namePtr -> HWND? in
                    CreateWindowExW(
                        0, namePtr, namePtr,
                        0, 0, 0, 0, 0,
                        hwndMessage, nil, instance, nil)
                }
            }
            if hwnd == nil {
                log.warning("CreateWindowExW(HWND_MESSAGE) failed (GetLastError=\(GetLastError())); relay disabled")
            } else {
                log.info("Primary single-instance receiver installed (\(className))")
            }
            return .primary
        }

        private static let receiverWndProc:
            @convention(c) (
                HWND?, UINT, WPARAM, LPARAM
            ) -> LRESULT = { hwnd, msg, wparam, lparam in
                // WM_COPYDATA는 항상 송신 스레드가 차단된 채 수신측에서 처리되는데
                // 수신측 메시지 펌프(즉 우리 메인 스레드)에서 풀리는 것이 정상.
                // 그러나 SendMessage가 다른 스레드에서 호출되어 `Win32App.unsafelyAssumeMainActor`
                // 가 트립되는 일을 막기 위해 가드한다(0xC000041D 회피).
                // 생명주기 메시지는 `DefWindowProcW`로 흘리면 우리 정리 경로를 우회하므로
                // 메인 스레드 큐에 재전송한다.
                let mainTID = Win32App.mainThreadID
                if let hwnd, mainTID != 0 && GetCurrentThreadId() != mainTID {
                    switch Int32(msg) {
                    case WM_CLOSE, WM_DESTROY, WM_NCDESTROY:
                        _ = PostMessageW(hwnd, msg, wparam, lparam)
                        return 0
                    default:
                        return DefWindowProcW(hwnd, msg, wparam, lparam)
                    }
                }
                if msg == UINT(WM_COPYDATA), lparam != 0 {
                    let raw = UnsafeMutableRawPointer(bitPattern: Int(lparam))
                    if let raw {
                        let cds = raw.assumingMemoryBound(to: COPYDATASTRUCT.self).pointee
                        let args = decodeArgs(cbData: cds.cbData, lpData: cds.lpData)
                        Win32App.unsafelyAssumeMainActor {
                            Self.copyDataHandler?(args)
                        }
                        return 1
                    }
                }
                return DefWindowProcW(hwnd, msg, wparam, lparam)
            }

        // MARK: - Secondary path

        private static func relayArguments(
            args: [String],
            className: String,
            log: Logger
        ) {
            // 수신자는 HWND_MESSAGE에 부착된 메시지 전용 윈도우이므로
            // 데스크톱 윈도우 목록에는 노출되지 않는다. `FindWindowExW`의
            // hwndParent로 반드시 HWND_MESSAGE(-3)를 지정해야 한다.
            let hwndMessage = HWND(bitPattern: -3)
            let target: HWND? = className.withUTF16Pointer {
                FindWindowExW(hwndMessage, nil, $0, nil)
            }
            guard let target else {
                log.warning("Could not locate primary single-instance window; arguments not forwarded")
                return
            }
            let payload = encodeArgs(args)
            // 기본 인스턴스의 UI 스레드가 모달 다이얼로그/장기 작업으로
            // 점유 중일 수 있다. `SendMessageW`는 무한 대기하므로 두 번째
            // 인스턴스가 영구히 블록될 위험이 있다. `SendMessageTimeoutW`
            // (`SMTO_ABORTIFHUNG | SMTO_NORMAL`, 5000ms)로 안전하게 회피한다.
            // 결과와 무관하게 secondary는 종료 흐름을 따른다.
            var delivered = false
            payload.withUnsafeBufferPointer { buf in
                var cds = COPYDATASTRUCT(
                    dwData: 0,
                    cbData: DWORD(buf.count * MemoryLayout<UInt16>.size),
                    lpData: UnsafeMutableRawPointer(mutating: buf.baseAddress))
                withUnsafeMutablePointer(to: &cds) { ptr in
                    var result: DWORD_PTR = 0
                    let rc = SendMessageTimeoutW(
                        target, UINT(WM_COPYDATA), 0,
                        LPARAM(Int(bitPattern: UnsafeRawPointer(ptr))),
                        UINT(SMTO_ABORTIFHUNG | SMTO_NORMAL),
                        5000,
                        &result)
                    delivered = rc != 0
                }
            }
            if delivered {
                log.info("Forwarded \(args.count) argument(s) to primary instance")
            } else {
                let err = GetLastError()
                log.warning(
                    "WM_COPYDATA forward to primary instance timed out or failed (GetLastError=\(err)); secondary will exit anyway"
                )
            }
        }

        // MARK: - Wire format

        /// Args are encoded as UTF-16 code units joined by `\u{0001}`
        /// (a control character that is illegal in normal CLI arguments).
        private static func encodeArgs(_ args: [String]) -> [UInt16] {
            let joined = args.joined(separator: "\u{0001}")
            return Array(joined.utf16)
        }

        private static func decodeArgs(cbData: DWORD, lpData: UnsafeMutableRawPointer?) -> [String] {
            guard let lpData, cbData > 0 else { return [] }
            let count = Int(cbData) / MemoryLayout<UInt16>.size
            let buffer = lpData.bindMemory(to: UInt16.self, capacity: count)
            let units = UnsafeBufferPointer(start: buffer, count: count)
            let str = String(decoding: units, as: UTF16.self)
            return str.split(separator: "\u{0001}", omittingEmptySubsequences: false).map(String.init)
        }
    }
#endif
