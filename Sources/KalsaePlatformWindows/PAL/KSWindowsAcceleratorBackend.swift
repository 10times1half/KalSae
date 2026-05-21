#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    internal import Foundation

    /// Win32 `RegisterHotKey` / `WM_HOTKEY` 기반의 `KSAcceleratorBackend` 구현체.
    /// 여기에 등록된 단축키는 시스템 전역(foreground 앱과 무관하게)에서 동작한다.
    ///
    /// `RegisterHotKey(nil, ...)` 는 호출 스레드의 메시지 큐에 `WM_HOTKEY` 를
    /// 게시하므로 반드시 UI 스레드(메시지 펌프를 도는 스레드)에서 호출해야
    /// 한다. 따라서 실제 Win32 호출만 `Win32App.runOnUIThread` 로 위임하고,
    /// 클래스 자체는 nonisolated 로 유지해 `async` 메서드가 blocked main
    /// thread 의 MainActor executor 로 hop 하지 않도록 한다.
    public final class KSWindowsAcceleratorBackend: KSAcceleratorBackend, @unchecked Sendable {
        private struct Entry {
            let hotKeyID: Int32
            let handler: @Sendable () -> Void
        }

        private let lock = NSLock()
        private var entries: [String: Entry] = [:]
        private var nextID: Int32 = 1
        private var routerInstalled: Bool = false
        private let log = KSLog.logger("platform.windows.accelerator")

        public init() {}

        public func register(
            id: String,
            accelerator: String,
            _ handler: @Sendable @escaping () -> Void
        ) async throws(KSError) {
            // 동일 id 이전 바인딩을 먼저 교체한다.
            try await unregister(id: id)

            guard let parsed = AcceleratorParser.parse(accelerator) else {
                throw KSError(
                    code: .invalidArgument,
                    message: "Could not parse accelerator: \(accelerator)")
            }

            installHotKeyRouterIfNeeded()

            let hotKeyID: Int32 = locked {
                let id = nextID
                nextID &+= 1
                return id
            }

            let modifiers = UINT(parsed.modifiers | UInt32(MOD_NOREPEAT))
            let vk = UINT(parsed.vk)

            // RegisterHotKey 는 UI 스레드 (메시지 펌프 소유) 에서만 의미가 있다.
            let ok = Win32App.runOnUIThread { () -> Bool in
                RegisterHotKey(nil, hotKeyID, modifiers, vk)
            }
            guard ok else {
                let err = Win32App.runOnUIThread { GetLastError() }
                throw KSError(
                    code: .platformInitFailed,
                    message: "RegisterHotKey failed for '\(accelerator)' (GetLastError=\(err))")
            }

            locked {
                entries[id] = Entry(hotKeyID: hotKeyID, handler: handler)
            }
            log.info("Registered hot-key '\(accelerator)' as id='\(id)' (hkid=\(hotKeyID))")
        }

        public func unregister(id: String) async throws(KSError) {
            let entry: Entry? = locked { entries.removeValue(forKey: id) }
            guard let entry else { return }
            let ok = Win32App.runOnUIThread { () -> Bool in
                UnregisterHotKey(nil, entry.hotKeyID)
            }
            if !ok {
                log.warning("UnregisterHotKey returned false for id='\(id)'")
            }
        }

        public func unregisterAll() async throws(KSError) {
            let snapshot: [String: Entry] = locked {
                let s = entries
                entries.removeAll()
                return s
            }
            for (id, entry) in snapshot {
                let ok = Win32App.runOnUIThread { () -> Bool in
                    UnregisterHotKey(nil, entry.hotKeyID)
                }
                if !ok {
                    log.warning("UnregisterHotKey returned false for id='\(id)'")
                }
            }
        }

        // MARK: - Internal

        /// `NSLock.lock/unlock` 는 async 컨텍스트에서 호출 시
        /// `unavailable from asynchronous contexts` 컴파일 에러가 발생한다.
        /// nonisolated 동기 헬퍼로 감싸 호출 시점의 isolation 을 끊는다.
        private func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }

        private func installHotKeyRouterIfNeeded() {
            let shouldInstall: Bool = locked {
                if routerInstalled { return false }
                routerInstalled = true
                return true
            }
            guard shouldInstall else { return }

            // UI 스레드 펌프가 직접 읽는 nonisolated 미러에 클로저를 심는다.
            // `Win32App.shared.hotKeyHandler` (@MainActor) 경유는 blocked
            // main thread 로 hop 하므로 사용 불가. 클로저는 UI 스레드에서
            // `Win32App.unsafelyAssumeMainActor` 안에서 호출되므로 nonisolated
            // 함수로 노출해도 안전하다.
            //
            // 클로저 body 는 `for ... where ...` 같은 stdlib sugar 를 피해
            // 명시적 for+if 로 풀어 dispatch_assert_queue 트랩을 방지한다
            // (`/memories/repo/windows-mainactor-closure-trap.md`).
            Win32App.hotKeyHandlerNonisolated = { [weak self] hkid in
                guard let self else { return }
                let found: (@Sendable () -> Void)? = self.locked {
                    var match: (@Sendable () -> Void)? = nil
                    for entry in self.entries.values {
                        if entry.hotKeyID == hkid {
                            match = entry.handler
                            break
                        }
                    }
                    return match
                }
                if let found {
                    found()
                }
            }
        }
    }

    // MARK: - Accelerator parser

    /// 크로스 플랫폼 단축키 문자열(예: `"CmdOrCtrl+Shift+N"`)을
    /// Win32 수식자 플래그와 가상 키 코드로 파싱한다.
    internal enum AcceleratorParser {
        struct Parsed {
            let modifiers: UInt32  // MOD_CONTROL | MOD_ALT | ...
            let vk: UInt32  // VK_*
        }

        static func parse(_ accelerator: String) -> Parsed? {
            let tokens =
                accelerator
                .split(separator: "+", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard !tokens.isEmpty else { return nil }

            var modifiers: UInt32 = 0
            var vk: UInt32? = nil

            for token in tokens {
                if let mod = modifierFlag(for: token) {
                    modifiers |= mod
                    continue
                }
                // 수식자가 아닌 첫 토큰이 키다.
                guard vk == nil, let code = virtualKey(for: token) else {
                    return nil
                }
                vk = code
            }
            guard let key = vk else { return nil }
            return Parsed(modifiers: modifiers, vk: key)
        }

        private static func modifierFlag(for token: String) -> UInt32? {
            switch token.lowercased() {
            case "ctrl", "control", "cmdorctrl", "commandorcontrol":
                return UInt32(MOD_CONTROL)
            case "shift":
                return UInt32(MOD_SHIFT)
            case "alt", "option":
                return UInt32(MOD_ALT)
            case "win", "super", "meta", "cmd", "command":
                return UInt32(MOD_WIN)
            default:
                return nil
            }
        }

        private static func virtualKey(for token: String) -> UInt32? {
            // 단일 문자: A-Z, 0-9, 일반 구두점.
            if token.count == 1, let scalar = token.unicodeScalars.first {
                let value = scalar.value
                // A-Z는 그대로
                if (0x41...0x5A).contains(value) { return value }
                // a-z → 대문자로
                if (0x61...0x7A).contains(value) { return value - 0x20 }
                // 0-9
                if (0x30...0x39).contains(value) { return value }
            }

            switch token.lowercased() {
            case "esc", "escape": return UInt32(VK_ESCAPE)
            case "tab": return UInt32(VK_TAB)
            case "enter", "return": return UInt32(VK_RETURN)
            case "space": return UInt32(VK_SPACE)
            case "backspace", "back": return UInt32(VK_BACK)
            case "delete", "del": return UInt32(VK_DELETE)
            case "insert", "ins": return UInt32(VK_INSERT)
            case "up": return UInt32(VK_UP)
            case "down": return UInt32(VK_DOWN)
            case "left": return UInt32(VK_LEFT)
            case "right": return UInt32(VK_RIGHT)
            case "home": return UInt32(VK_HOME)
            case "end": return UInt32(VK_END)
            case "pageup", "pgup": return UInt32(VK_PRIOR)
            case "pagedown", "pgdn": return UInt32(VK_NEXT)
            case "plus": return UInt32(VK_OEM_PLUS)
            case "minus": return UInt32(VK_OEM_MINUS)
            case "comma": return UInt32(VK_OEM_COMMA)
            case "period": return UInt32(VK_OEM_PERIOD)
            default: break
            }

            // F1..F24 기능키
            if token.count >= 2,
                let first = token.first, first == "F" || first == "f",
                let n = Int(token.dropFirst()),
                (1...24).contains(n)
            {
                return UInt32(VK_F1) + UInt32(n - 1)
            }

            return nil
        }
    }
#endif
