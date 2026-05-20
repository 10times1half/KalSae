#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    public import Foundation

    /// Win32 implementation of `KSDialogBackend`.
    ///
    /// Uses:
    ///   • `MessageBoxW` for `message`
    ///   • `IFileOpenDialog` (CLSID_FileOpenDialog) for open / folder picker
    ///   • `IFileSaveDialog` (CLSID_FileSaveDialog) for save
    ///
    /// 모던 Vista+ Common Item Dialog로 구현되어 있어 긴 경로(>MAX_PATH)와
    /// breadcrumb UI를 지원한다. 파일 다이얼로그 구현은
    /// `KSWindowsDialogBackend+Files.swift` + C++ 쉬밌(`kswv2_dialog.cpp`).
    ///
    /// All native calls run on the Win32 UI thread via
    /// `Win32App.runOnUIThread { … }` (NOT `MainActor.run` — Swift's main
    /// thread is blocked in `WaitForSingleObject(uiThread)` and would
    /// deadlock).
    public struct KSWindowsDialogBackend: KSDialogBackend, Sendable {
        public init() {}

        // MARK: - Message dialog

        public func message(
            _ options: KSMessageOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> KSMessageResult {
            let raw = Self._resolveHWND(parent)
            return Win32App.runOnUIThread {
                Self._messageOnMain(options, parentHWND: raw)
            }
        }

        /// Resolves a `KSWindowHandle` to a raw `HWND` pointer on the Win32 UI
        /// thread. The lookup itself accesses `@MainActor`-isolated state, but
        /// we keep the scope as narrow as possible so the surrounding dialog
        /// call can run on a nonisolated closure (avoiding the stdlib generic
        /// closure @MainActor trap documented in `+Files.swift`).
        ///
        /// Fallback: when `handle` is nil OR the registry has no matching
        /// HWND, returns `GetActiveWindow()` so the file picker is parented
        /// to the demo's foreground window. Without this, IFileOpenDialog
        /// can appear behind the WebView2 surface and look unresponsive.
        /// Also calls `SetForegroundWindow(hwnd)` to make sure the dialog
        /// pops to the top.
        nonisolated
        private static func _resolveHWND(_ handle: KSWindowHandle?) -> UnsafeMutableRawPointer? {
            Win32App.runOnUIThreadIsolated {
                // 명시적 if-let — `Optional.flatMap` / `Optional.map`은
                // @MainActor 클로저 안에서 호출되면 stdlib 콜백을 통해
                // dispatch_assert_queue 트랩을 일으킬 수 있다.
                var hwnd: HWND? = nil
                if let handle {
                    hwnd = KSWin32HandleRegistry.shared.hwnd(for: handle)
                }
                if hwnd == nil { hwnd = GetActiveWindow() }
                if hwnd == nil { hwnd = GetForegroundWindow() }
                guard let hwnd else { return nil }
                _ = SetForegroundWindow(hwnd)
                return UnsafeMutableRawPointer(hwnd)
            }
        }

        // NOTE: `_messageOnMain` is `nonisolated` (not `@MainActor`) even though
        // it must run on the Win32 UI thread. See the rationale in
        // `KSWindowsDialogBackend+Files.swift`: closures created inside a
        // `@MainActor` function are inferred `@MainActor` and trigger
        // `dispatch_assert_queue` when invoked by generic stdlib helpers, which
        // traps because the Win32 UI thread is not Swift's dispatch main queue.
        nonisolated
        private static func _messageOnMain(
            _ options: KSMessageOptions,
            parentHWND: UnsafeMutableRawPointer?
        ) -> KSMessageResult {
            let combined: String = {
                if let detail = options.detail, !detail.isEmpty {
                    return "\(options.message)\n\n\(detail)"
                }
                return options.message
            }()

            var flags: UINT = 0
            switch options.kind {
            case .info: flags |= UINT(MB_ICONINFORMATION)
            case .warning: flags |= UINT(MB_ICONWARNING)
            case .error: flags |= UINT(MB_ICONERROR)
            case .question: flags |= UINT(MB_ICONQUESTION)
            }
            switch options.buttons {
            case .ok: flags |= UINT(MB_OK)
            case .okCancel: flags |= UINT(MB_OKCANCEL)
            case .yesNo: flags |= UINT(MB_YESNO)
            case .yesNoCancel: flags |= UINT(MB_YESNOCANCEL)
            }

            let result = options.title.withUTF16Pointer { title in
                combined.withUTF16Pointer { msg in
                    MessageBoxW(
                        parentHWND.map { HWND(OpaquePointer($0)) },
                        msg, title, flags)
                }
            }

            switch result {
            case IDOK: return .ok
            case IDCANCEL: return .cancel
            case IDYES: return .yes
            case IDNO: return .no
            default: return .cancel
            }
        }

        // MARK: - File dialogs

        public func openFile(
            options: KSOpenFileOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> [URL] {
            let raw = Self._resolveHWND(parent)
            let box: KSSendableBox<[URL]> = Win32App.runOnUIThread {
                KSSendableBox(Self._openFileOnMain(options: options, parentHWND: raw))
            }
            return box.value
        }

        public func saveFile(
            options: KSSaveFileOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> URL? {
            let raw = Self._resolveHWND(parent)
            let box: KSSendableBox<URL?> = Win32App.runOnUIThread {
                KSSendableBox(Self._saveFileOnMain(options: options, parentHWND: raw))
            }
            return box.value
        }

        public func selectFolder(
            options: KSSelectFolderOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> URL? {
            let raw = Self._resolveHWND(parent)
            let box: KSSendableBox<URL?> = Win32App.runOnUIThread {
                KSSendableBox(Self._selectFolderOnMain(options: options, parentHWND: raw))
            }
            return box.value
        }

        // MARK: - Synchronous, UI-thread entry points
        //
        // 이미 UI 스레드 위에 있을 때 (예: `KSApp.postJob` 클로저 안)
        // 사용한다. async 프로토콜 메서드와 동일한 Win32 API를 `MainActor.run`
        // 홉 없이 구동한다. 이는 Win32의 `GetMessageW`가 Swift 협동 스케줄러를
        // 펄프하지 않기 때문이다 — 백그라운드 디스패치에서 `MainActor.run`을
        // await하면 다이얼로그가 데드락된다.

        @MainActor
        public static func messageOnUI(
            _ options: KSMessageOptions, parent: KSWindowHandle? = nil
        ) -> KSMessageResult {
            let hwnd = parent.flatMap { KSWin32HandleRegistry.shared.hwnd(for: $0) }
            let raw = hwnd.map { UnsafeMutableRawPointer($0) }
            return _messageOnMain(options, parentHWND: raw)
        }

        @MainActor
        public static func openFileOnUI(
            _ options: KSOpenFileOptions, parent: KSWindowHandle? = nil
        ) -> [URL] {
            let hwnd = parent.flatMap { KSWin32HandleRegistry.shared.hwnd(for: $0) }
            let raw = hwnd.map { UnsafeMutableRawPointer($0) }
            return _openFileOnMain(options: options, parentHWND: raw)
        }

        @MainActor
        public static func saveFileOnUI(
            _ options: KSSaveFileOptions, parent: KSWindowHandle? = nil
        ) -> URL? {
            let hwnd = parent.flatMap { KSWin32HandleRegistry.shared.hwnd(for: $0) }
            let raw = hwnd.map { UnsafeMutableRawPointer($0) }
            return _saveFileOnMain(options: options, parentHWND: raw)
        }

        @MainActor
        public static func selectFolderOnUI(
            _ options: KSSelectFolderOptions, parent: KSWindowHandle? = nil
        ) -> URL? {
            let hwnd = parent.flatMap { KSWin32HandleRegistry.shared.hwnd(for: $0) }
            let raw = hwnd.map { UnsafeMutableRawPointer($0) }
            return _selectFolderOnMain(options: options, parentHWND: raw)
        }

        // MARK: - File dialog implementation — see `KSWindowsDialogBackend+Files.swift`.
    }
#endif
