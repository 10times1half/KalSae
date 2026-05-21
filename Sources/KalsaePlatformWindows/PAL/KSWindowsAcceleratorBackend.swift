#if os(Windows)
    internal import WinSDK
    public import KalsaeCore

    /// Win32 `RegisterHotKey` / `WM_HOTKEY` 기반의 `KSAcceleratorBackend` 구현체.
    /// 여기에 등록된 단축키는 시스템 전역(foreground 앱과 무관하게)에서 동작한다.
    ///
    /// 등록은 반드시 UI 스레드(`Win32App.runMessageLoop`이 실행 중인 스레드)에서
    /// 이루어져야 한다. `@MainActor` 격리로 이를 강제한다.
    @MainActor
    public final class KSWindowsAcceleratorBackend: KSAcceleratorBackend {
        private struct Entry {
            let hotKeyID: Int32
            let handler: @Sendable () -> Void
        }

        private var entries: [String: Entry] = [:]
        private var nextID: Int32 = 1
        private let log = KSLog.logger("platform.windows.accelerator")

        public nonisolated init() {}

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

            try installHotKeyRouterIfNeeded()

            let hotKeyID = nextID
            nextID &+= 1

            let modifiers = UINT(parsed.modifiers | UInt32(MOD_NOREPEAT))
            let vk = UINT(parsed.vk)

            guard RegisterHotKey(nil, hotKeyID, modifiers, vk) else {
                let err = GetLastError()
                throw KSError(
                    code: .platformInitFailed,
                    message: "RegisterHotKey failed for '\(accelerator)' (GetLastError=\(err))")
            }

            entries[id] = Entry(hotKeyID: hotKeyID, handler: handler)
            log.info("Registered hot-key '\(accelerator)' as id='\(id)' (hkid=\(hotKeyID))")
        }

        public func unregister(id: String) async throws(KSError) {
            guard let entry = entries.removeValue(forKey: id) else { return }
            if !UnregisterHotKey(nil, entry.hotKeyID) {
                log.warning("UnregisterHotKey returned false for id='\(id)' (GetLastError=\(GetLastError()))")
            }
        }

        public func unregisterAll() async throws(KSError) {
            for (id, entry) in entries {
                if !UnregisterHotKey(nil, entry.hotKeyID) {
                    log.warning("UnregisterHotKey returned false for id='\(id)' (GetLastError=\(GetLastError()))")
                }
            }
            entries.removeAll()
        }

        // MARK: - Internal

        private func installHotKeyRouterIfNeeded() throws(KSError) {
            guard Win32App.shared.hotKeyHandler == nil else { return }
            Win32App.shared.hotKeyHandler = { [weak self] hkid in
                guard let self else { return }
                for entry in self.entries.values where entry.hotKeyID == hkid {
                    entry.handler()
                    return
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
