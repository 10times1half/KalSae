#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    internal import Foundation

    /// Win32 tray icon backend (`Shell_NotifyIconW`).
    ///
    /// Uses a hidden message-only window to receive the tray callback
    /// (`WM_USER+20`) so click/right-click → menu routing is independent of
    /// any visible window. Menu clicks land in WM_COMMAND on the same
    /// message-only window and are forwarded to `KSWindowsCommandRouter`.
    @MainActor
    public final class KSWindowsTrayBackend: KSTrayBackend {
        public nonisolated init() {}

        internal static let trayCallbackMessage: UINT = UINT(WM_USER) + 20

        internal var messageWindow: HWND?
        private var iconHandle: HICON?
        private var installed: Bool = false
        private var currentTooltip: String = ""
        internal var currentMenuItems: [KSMenuItem] = []
        internal var onLeftClickCommand: String?
        private static let iconUID: UINT = 0xA001

        nonisolated public func install(_ config: KSTrayConfig) async throws(KSError) {
            let result: Result<Void, KSError> = await MainActor.run {
                self._installResult(config)
            }
            try result.unwrap()
        }

        nonisolated public func setTooltip(_ tooltip: String) async throws(KSError) {
            let result: Result<Void, KSError> = await MainActor.run {
                self._setTooltipResult(tooltip)
            }
            try result.unwrap()
        }

        nonisolated public func setMenu(_ items: [KSMenuItem]) async throws(KSError) {
            await MainActor.run {
                self.currentMenuItems = items
            }
        }

        nonisolated public func remove() async {
            await MainActor.run {
                self._removeOnMain()
            }
        }

        // MARK: - UI-thread implementation

        /// Synchronous install used internally by `install(_:)` and by the
        /// notification backend's transient-icon path.
        @MainActor
        internal func installSync(_ config: KSTrayConfig) throws(KSError) {
            try _installOnMain(config)
        }

        /// Synchronous remove counterpart.
        @MainActor
        internal func removeSync() {
            _removeOnMain()
        }

        @MainActor
        private func _installResult(_ config: KSTrayConfig) -> Result<Void, KSError> {
            // `_installOnMain`은 `throws(KSError)`만 하므로 bare `catch`가
            // 자동으로 `error: KSError`로 바인딩된다.
            do {
                try _installOnMain(config)
                return .success(())
            } catch { return .failure(error) }
        }

        @MainActor
        private func _setTooltipResult(_ tooltip: String) -> Result<Void, KSError> {
            do {
                try _setTooltipOnMain(tooltip)
                return .success(())
            } catch { return .failure(error) }
        }

        private func _installOnMain(_ config: KSTrayConfig) throws(KSError) {
            try ensureMessageWindow()
            let icon = try loadIcon(path: config.icon)
            var data = NOTIFYICONDATAW()
            data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
            data.hWnd = messageWindow
            data.uID = Self.iconUID
            data.uFlags = UINT(NIF_ICON | NIF_MESSAGE | NIF_TIP)
            data.uCallbackMessage = Self.trayCallbackMessage
            data.hIcon = icon
            Self.fillTooltip(&data, tooltip: config.tooltip ?? "")

            let action: DWORD = installed ? DWORD(NIM_MODIFY) : DWORD(NIM_ADD)
            guard Shell_NotifyIconW(action, &data) else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "Shell_NotifyIconW (\(installed ? "modify" : "add")) failed")
            }

            if let old = iconHandle, old != icon {
                DestroyIcon(old)
            }
            self.iconHandle = icon
            self.installed = true
            self.currentTooltip = config.tooltip ?? ""
            self.currentMenuItems = config.menu ?? []
            self.onLeftClickCommand = config.onLeftClick
        }

        private func _setTooltipOnMain(_ tooltip: String) throws(KSError) {
            guard installed else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "Tray not installed.")
            }
            var data = NOTIFYICONDATAW()
            data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
            data.hWnd = messageWindow
            data.uID = Self.iconUID
            data.uFlags = UINT(NIF_TIP)
            Self.fillTooltip(&data, tooltip: tooltip)
            guard Shell_NotifyIconW(DWORD(NIM_MODIFY), &data) else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "Shell_NotifyIconW (modify tip) failed")
            }
            currentTooltip = tooltip
        }

        private func _removeOnMain() {
            guard installed else { return }
            var data = NOTIFYICONDATAW()
            data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
            data.hWnd = messageWindow
            data.uID = Self.iconUID
            _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &data)
            if let icon = iconHandle { DestroyIcon(icon) }
            iconHandle = nil
            installed = false
        }

        /// Used by `KSWindowsNotificationBackend` to post a balloon-style
        /// toast through the same icon registration. Returns `false` if the
        /// tray is not installed.
        @discardableResult
        func showBalloon(title: String, message: String, kind: KSMessageOptions.Kind) -> Bool {
            guard installed else { return false }
            var data = NOTIFYICONDATAW()
            data.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
            data.hWnd = messageWindow
            data.uID = Self.iconUID
            data.uFlags = UINT(NIF_INFO)
            Self.fill(&data.szInfo, "\(message)")
            Self.fill(&data.szInfoTitle, "\(title)")
            switch kind {
            case .info: data.dwInfoFlags = DWORD(NIIF_INFO)
            case .warning: data.dwInfoFlags = DWORD(NIIF_WARNING)
            case .error: data.dwInfoFlags = DWORD(NIIF_ERROR)
            case .question: data.dwInfoFlags = DWORD(NIIF_INFO)
            }
            return Shell_NotifyIconW(DWORD(NIM_MODIFY), &data)
        }

        // MARK: - Hidden message-only window — see `KSWindowsTrayBackend+MessageWindow.swift`.

        internal static var registeredClass = false
        internal static let messageWindowClass = "KalsaeTray"
        internal static var trayWindowHWND: UInt = 0
        internal static weak var activeBackend: KSWindowsTrayBackend?

        // MARK: - Helpers

        private func loadIcon(path: String) throws(KSError) -> HICON {
            let resolved = Self.resolveIconPath(path)

            // .ico 파일은 LoadImageW + LR_LOADFROMFILE, 사용되지 못하면 기본
            // 애플리케이션 아이콘으로 폴백해 트레이를 표시한다.
            if let resolved {
                let icon = resolved.path.withUTF16Pointer { ptr in
                    LoadImageW(
                        nil, ptr, UINT(IMAGE_ICON), 0, 0,
                        UINT(LR_LOADFROMFILE) | UINT(LR_DEFAULTSIZE))
                }
                if let icon {
                    return HICON(OpaquePointer(icon))
                }
            }

            // 폴백: 기본 애플리케이션 아이콘.
            let stock = LoadIconW(nil, UnsafePointer<UInt16>(bitPattern: 32512))
            guard let stock else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "Failed to load fallback tray icon")
            }
            return stock
        }

        private static func resolveIconPath(_ raw: String) -> URL? {
            if FileManager.default.fileExists(atPath: raw) {
                return URL(fileURLWithPath: raw)
            }
            return nil
        }

        /// Copies up to N-1 UTF-16 code units of `s` into `tuple`, NUL-terminating.
        private static func fill<T>(_ tuple: inout T, _ s: String) {
            withUnsafeMutableBytes(of: &tuple) { rawBuf in
                guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt16.self)
                else { return }
                let cap = rawBuf.count / MemoryLayout<UInt16>.stride
                var i = 0
                for c in s.utf16 where i < cap - 1 {
                    base[i] = c
                    i += 1
                }
                base[i] = 0
            }
        }

        private static func fillTooltip(_ data: inout NOTIFYICONDATAW, tooltip: String) {
            Self.fill(&data.szTip, tooltip)
        }
    }
#endif
