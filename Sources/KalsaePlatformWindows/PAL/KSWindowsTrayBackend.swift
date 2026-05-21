#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    internal import Foundation

    // MARK: - KSWindowsTrayBackend

    /// Win32 트레이 아이콘 백엔드 (`Shell_NotifyIconW`).
    ///
    /// 숨겨진 message-only 윈도우를 사용해 트레이 콜백(`WM_USER+20`)을
    /// 수신하므로, 클릭/우클릭 → 메뉴 라우팅이 어떤 가시 윈도우에도
    /// 종속되지 않는다. 메뉴 클릭은 동일한 message-only 윈도우의
    /// WM_COMMAND로 전달되며 `KSWindowsCommandRouter`로 포워딩된다.
    ///
    /// ## 동작 개요
    /// - `install(_:)`: `NIM_ADD`로 아이콘 등록 (이미 설치된 경우 `NIM_MODIFY`)
    /// - `setTooltip(_:)`: `NIM_MODIFY` + `NIF_TIP` 플래그로 툴팁 갱신
    /// - `setMenu(_:)`: 메뉴 아이템 목록만 메모리에 저장 — 실제 메뉴는
    ///   우클릭 시점에 `TrackPopupMenu`로 생성
    /// - `remove()`: `NIM_DELETE`로 아이콘 등록 해제
    @MainActor
    public final class KSWindowsTrayBackend: KSTrayBackend {
        public nonisolated init() {}

        // ─── 트레이 콜백 메시지 상수 ───────────────────────────────
        /// `WM_USER + 20` — 트레이 아이콘에서 발생하는 마우스/키보드
        /// 이벤트를 수신하기 위한 사용자 정의 메시지 ID.
        /// `NOTIFYICONDATAW.uCallbackMessage`에 설정된다.
        internal static let trayCallbackMessage: UINT = UINT(WM_USER) + 20

        // ─── 내부 상태 ─────────────────────────────────────────────
        /// 트레이 콜백을 수신하는 message-only 윈도우의 HWND.
        internal var messageWindow: HWND?
        /// 현재 표시 중인 트레이 아이콘의 `HICON` 핸들 (DestroyIcon 필요).
        private var iconHandle: HICON?
        /// `Shell_NotifyIconW(NIM_ADD)`가 성공했는지 여부.
        private var installed: Bool = false
        /// 마지막으로 설정된 툴팁 문자열 (재설치 시 복원용).
        private var currentTooltip: String = ""
        /// 현재 메뉴 아이템 목록 — 우클릭 시 `showTrayMenu()`가 읽는다.
        internal var currentMenuItems: [KSMenuItem] = []
        /// 왼쪽 클릭 시 실행할 명령어 (`config.onLeftClick`에서 설정).
        internal var onLeftClickCommand: String?
        /// 트레이 아이콘의 고유 식별자 (0xA001). 같은 `hWnd` 내에서
        /// 여러 아이콘을 구분하는 데 사용된다.
        private static let iconUID: UINT = 0xA001

        // ─── KSTrayBackend 프로토콜 구현 ──────────────────────────

        /// 트레이 아이콘을 설치(등록)한다.
        ///
        /// 1. `ensureMessageWindow()`로 message-only 윈도우 생성
        /// 2. `loadIcon()`으로 `.ico` 파일 로드 (실패 시 기본 앱 아이콘 폴백)
        /// 3. `NOTIFYICONDATAW` 구조체를 채워 `Shell_NotifyIconW(NIM_ADD)` 호출
        /// 4. 이미 설치된 경우 `NIM_MODIFY`로 갱신 (재진입 안전)
        nonisolated public func install(_ config: KSTrayConfig) async throws(KSError) {
            let result: Result<Void, KSError> = Win32App.runOnUIThreadIsolated {
                self._installResult(config)
            }
            try result.unwrap()
        }

        /// 툴팁 문자열을 갱신한다. 내부적으로 `NIM_MODIFY` + `NIF_TIP`을 사용한다.
        nonisolated public func setTooltip(_ tooltip: String) async throws(KSError) {
            let result: Result<Void, KSError> = Win32App.runOnUIThreadIsolated {
                self._setTooltipResult(tooltip)
            }
            try result.unwrap()
        }

        /// 우클릭 컨텍스트 메뉴에 표시할 `KSMenuItem` 배열을 설정한다.
        /// 실제 윈도우 메뉴 생성은 `showTrayMenu()`에서 `TrackPopupMenu`로
        /// 지연 생성된다.
        nonisolated public func setMenu(_ items: [KSMenuItem]) async throws(KSError) {
            Win32App.runOnUIThreadIsolated {
                self.currentMenuItems = items
            }
        }

        /// 트레이 아이콘을 제거한다 (`NIM_DELETE`).
        /// 아이콘 핸들을 파괴하고 `installed = false`로 설정한다.
        nonisolated public func remove() async {
            Win32App.runOnUIThreadIsolated {
                self._removeOnMain()
            }
        }

        // MARK: - UI-스레드 구현체

        /// `installSync(_:)` — `install(_:)` 및 알림 백엔드의
        /// transient-icon 경로에서 사용되는 동기 설치 메서드.
        ///
        /// `KSTrayBackend` 프로토콜 메서드는 `async nonisolated`이지만,
        /// `KSWindowsNotificationBackend`는 `@MainActor` 컨텍스트 안에서
        /// 트레이 설치가 필요할 때 이 메서드를 직접 호출한다.
        @MainActor
        internal func installSync(_ config: KSTrayConfig) throws(KSError) {
            try _installOnMain(config)
        }

        /// `removeSync()` — 동기 제거 메서드.
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

        // ─── 실제 Win32 호출부 ────────────────────────────────────

        /// `@MainActor` 격리된 실제 설치 로직.
        ///
        /// `NOTIFYICONDATAW` 구조체 설명:
        /// - `cbSize`: 구조체 크기 (버전 호환성 보장)
        /// - `hWnd`: 콜백 메시지를 받을 message-only 윈도우
        /// - `uID`: 같은 `hWnd` 내 아이콘 식별자 (0xA001)
        /// - `uFlags`:
        ///   - `NIF_ICON`: `hIcon` 필드 사용
        ///   - `NIF_MESSAGE`: `uCallbackMessage` 필드 사용 (트레이 콜백)
        ///   - `NIF_TIP`: `szTip` 필드 사용 (툴팁)
        /// - `uCallbackMessage`: `WM_USER + 20` — 트레이 이벤트용 사용자 정의 메시지
        /// - `hIcon`: 로드한 아이콘의 `HICON` 핸들
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

            // 이미 설치된 경우 `NIM_MODIFY`로 갱신, 최초 설치 시 `NIM_ADD`
            let action: DWORD = installed ? DWORD(NIM_MODIFY) : DWORD(NIM_ADD)
            guard Shell_NotifyIconW(action, &data) else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "Shell_NotifyIconW (\(installed ? "modify" : "add")) failed")
            }

            // 이전 아이콘 핸들이 있으면 해제 (중복 로드 방지)
            if let old = iconHandle, old != icon {
                DestroyIcon(old)
            }
            self.iconHandle = icon
            self.installed = true
            self.currentTooltip = config.tooltip ?? ""
            self.currentMenuItems = config.menu ?? []
            self.onLeftClickCommand = config.onLeftClick
        }

        /// 툴팁 문자열만 갱신 (`NIM_MODIFY` + `NIF_TIP`).
        /// 아이콘이나 콜백 메시지는 변경하지 않는다.
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

        /// 트레이 아이콘 등록 해제 (`NIM_DELETE`).
        /// 아이콘 핸들을 `DestroyIcon`으로 정리하고 플래그를 재설정한다.
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

        /// `KSWindowsNotificationBackend`에서 사용 — 같은 아이콘 등록을
        /// 통해 풍선 스타일 토스트를 표시한다.
        ///
        /// `NIF_INFO` 플래그로 `NIM_MODIFY`를 호출하여 `szInfo`/`szInfoTitle`
        /// 필드의 내용을 풍선/토스트로 표시한다.
        /// - Windows 10+에서는 표준 알림 센터 토스트로 표시된다.
        /// - `NIIF_*` 상수로 아이콘 종류를 지정한다 (`NIIF_INFO`/`NIIF_WARNING`/`NIIF_ERROR`).
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
            case .question: data.dwInfoFlags = DWORD(NIIF_INFO)  // 질문 아이콘은 정보 아이콘으로 대체
            }
            return Shell_NotifyIconW(DWORD(NIM_MODIFY), &data)
        }

        // MARK: - 숨겨진 message-only 윈도우 — `KSWindowsTrayBackend+MessageWindow.swift` 참고.

        internal static var registeredClass = false
        internal static let messageWindowClass = "KalsaeTray"
        internal static var trayWindowHWND: UInt = 0
        internal static weak var activeBackend: KSWindowsTrayBackend?

        // MARK: - 헬퍼

        /// 아이콘 파일 경로에서 `HICON`을 로드한다.
        ///
        /// 1. `resolveIconPath()`로 경로 존재 여부 확인
        /// 2. 존재하면 `LoadImageW(LR_LOADFROMFILE | LR_DEFAULTSIZE)`로 `.ico` 로드
        /// 3. 실패하거나 경로가 없으면 `LoadIconW(IDI_APPLICATION)`로 기본 아이콘 폴백
        ///
        /// `LR_DEFAULTSIZE`는 시스템 기본 크기(SM_CXICON × SM_CYICON)로
        /// 로드하도록 한다.
        private func loadIcon(path: String) throws(KSError) -> HICON {
            let resolved = Self.resolveIconPath(path)

            // .ico 파일은 `LoadImageW` + `LR_LOADFROMFILE`로 로드한다.
            // 파일이 존재하지 않거나 로드에 실패하면 기본 애플리케이션
            // 아이콘으로 폴백해 트레이가 항상 표시되도록 보장한다.
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

            // 폴백: `IDI_APPLICATION`(32512) — 기본 애플리케이션 아이콘.
            let stock = LoadIconW(nil, UnsafePointer<UInt16>(bitPattern: 32512))
            guard let stock else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "Failed to load fallback tray icon")
            }
            return stock
        }

        /// 아이콘 경로 문자열이 유효한 파일 경로인지 확인한다.
        /// 파일이 존재하면 `URL`을 반환, 없으면 `nil`.
        private static func resolveIconPath(_ raw: String) -> URL? {
            if FileManager.default.fileExists(atPath: raw) {
                return URL(fileURLWithPath: raw)
            }
            return nil
        }

        /// `tuple`(주로 `NOTIFYICONDATAW`의 고정 크기 `WCHAR` 배열)에
        /// UTF-16 문자열 `s`를 최대 N-1 코드 유닛까지 복사하고 NUL로 종결한다.
        ///
        /// ---
        /// **`nonisolated`가 중요한 이유:**
        ///
        /// `withUnsafeMutableBytes`는 stdlib 제네릭 헬퍼이며, `@MainActor`
        /// 컨텍스트에서 호출하면 클로저가 `@MainActor`로 추론된다. 그런데
        /// Kalsae의 Win32 UI 스레드는 전용 Win32 스레드이지 Swift의
        /// dispatch main queue가 아니므로, `@MainActor` 클로저 내에서
        /// `dispatch_assert_queue` 트랩(`STATUS_ILLEGAL_INSTRUCTION`
        /// 0xC000001D)이 발생한다.
        ///
        /// 이 메서드를 `nonisolated`로 선언하면 `@MainActor` 격리 전파가
        /// 차단되어, UI 스레드에서 안전하게 호출할 수 있다.
        ///
        /// 자세한 내용은 `Docs/SECURITY.md` 및
        /// `/memories/repo/windows-mainactor-closure-trap.md` 참고.
        /// ---
        nonisolated private static func fill<T>(_ tuple: inout T, _ s: String) {
            withUnsafeMutableBytes(of: &tuple) { rawBuf in
                guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt16.self)
                else { return }
                let cap = rawBuf.count / MemoryLayout<UInt16>.stride
                var i = 0
                for c in s.utf16 where i < cap - 1 {
                    base[i] = c
                    i += 1
                }
                base[i] = 0  // NUL 종결
            }
        }

        /// `NOTIFYICONDATAW.szTip` (128 WCHAR)에 툴팁 문자열을 채운다.
        nonisolated private static func fillTooltip(_ data: inout NOTIFYICONDATAW, tooltip: String) {
            Self.fill(&data.szTip, tooltip)
        }
    }
#endif
