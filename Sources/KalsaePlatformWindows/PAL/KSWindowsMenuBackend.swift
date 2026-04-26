#if os(Windows)
internal import WinSDK
public import KalsaeCore
public import Foundation

/// Routes WM_COMMAND clicks back to a Kalsae command id. The
/// table is shared between every menu we install in the process: the
/// app menubar, window menus, tray menus, and context menus.
@MainActor
internal final class KSWin32MenuRegistry {
    static let shared = KSWin32MenuRegistry()

    /// Reserved low range so menu ids never collide with WM_COMMAND
    /// notifications coming from controls or accelerators.
    private var nextID: UInt32 = 0x8001
    private var idToCommand: [UInt32: String] = [:]
    private var idToItemID: [UInt32: String] = [:]

    private init() {}

    /// Allocates a fresh Win32 menu id, remembering the Kalsae `command`
    /// (e.g. `"file.open"`) and `itemID` (e.g. `"open"`) that produced it.
    func allocate(command: String?, itemID: String?) -> UInt32 {
        let id = nextID
        // 컨트롤 ID 공간에 도달하기 전에 순환시킨다.
        if nextID == 0xBFFF { nextID = 0x8001 } else { nextID += 1 }
        if let c = command  { idToCommand[id] = c }
        if let i = itemID   { idToItemID[id]  = i }
        return id
    }

    /// Looks up the command associated with a Win32 menu id.
    func resolve(id: UInt32) -> (command: String?, itemID: String?) {
        (idToCommand[id], idToItemID[id])
    }
}

/// Win32 implementation of `KSMenuBackend`. Menus are HMENU trees managed
/// on the UI thread; clicks come back as `WM_COMMAND(LOWORD(wparam))`.
public struct KSWindowsMenuBackend: KSMenuBackend, Sendable {
    public init() {}

    /// Installs `items` as the menubar of every currently-tracked top-level
    /// window. With Phase 8's single-window model that means the demo's
    /// main window.
    public func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) {
        let result: Result<Void, KSError> = await MainActor.run {
            Self._installAppMenuOnMain(items)
        }
        try result.unwrap()
    }

    public func installWindowMenu(
        _ handle: KSWindowHandle,
        items: [KSMenuItem]
    ) async throws(KSError) {
        let result: Result<Void, KSError> = await MainActor.run {
            Self._installWindowMenuOnMain(handle: handle, items: items)
        }
        try result.unwrap()
    }

    public func showContextMenu(
        _ items: [KSMenuItem],
        at point: KSPoint,
        in handle: KSWindowHandle?
    ) async throws(KSError) {
        let result: Result<Void, KSError> = await MainActor.run {
            Self._showContextMenuOnMain(items: items, at: point, in: handle)
        }
        try result.unwrap()
    }

    // MARK: - UI-thread implementation

    @MainActor
    private static func _installAppMenuOnMain(
        _ items: [KSMenuItem]
    ) -> Result<Void, KSError> {
        // `buildMenu`는 `throws(KSError)`만 하므로 bare `catch`가 KSError로
        // 자동 바인딩된다.
        do {
            let menu = try Self.buildMenu(items, isPopup: false)
            for hwnd in KSWin32MainWindowTracker.shared.allWindowHWNDs() {
                let old = GetMenu(hwnd)
                _ = SetMenu(hwnd, menu)
                _ = DrawMenuBar(hwnd)
                if let old { DestroyMenu(old) }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    private static func _installWindowMenuOnMain(
        handle: KSWindowHandle, items: [KSMenuItem]
    ) -> Result<Void, KSError> {
        guard let hwnd = KSWin32HandleRegistry.shared.hwnd(for: handle) else {
            return .failure(KSError(code: .platformInitFailed,
                                    message: "No HWND for window '\(handle.label)'."))
        }
        do {
            let menu = try Self.buildMenu(items, isPopup: false)
            let old = GetMenu(hwnd)
            _ = SetMenu(hwnd, menu)
            _ = DrawMenuBar(hwnd)
            if let old { DestroyMenu(old) }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    private static func _showContextMenuOnMain(
        items: [KSMenuItem],
        at point: KSPoint,
        in handle: KSWindowHandle?
    ) -> Result<Void, KSError> {
        do {
            let menu = try Self.buildMenu(items, isPopup: true)
            defer { DestroyMenu(menu) }

            let hwnd = handle.flatMap { KSWin32HandleRegistry.shared.hwnd(for: $0) }
                       ?? GetActiveWindow()
            guard let hwnd else {
                return .failure(KSError(code: .platformInitFailed,
                                        message: "No window to anchor context menu."))
            }
            _ = SetForegroundWindow(hwnd)
            _ = TrackPopupMenu(
                menu,
                UINT(TPM_RIGHTBUTTON | TPM_LEFTALIGN | TPM_TOPALIGN),
                Int32(point.x), Int32(point.y),
                0, hwnd, nil)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - HMENU construction

    @MainActor
    internal static func buildMenu(
        _ items: [KSMenuItem],
        isPopup: Bool
    ) throws(KSError) -> HMENU {
        guard let menu = isPopup ? CreatePopupMenu() : CreateMenu() else {
            throw KSError(code: .platformInitFailed,
                          message: "CreateMenu failed (GetLastError=\(GetLastError()))")
        }
        for item in items {
            try appendItem(item, into: menu)
        }
        return menu
    }

    @MainActor
    private static func appendItem(
        _ item: KSMenuItem,
        into parent: HMENU
    ) throws(KSError) {
        switch item.kind {
        case .separator:
            _ = AppendMenuW(parent, UINT(MF_SEPARATOR), 0, nil)

        case .submenu:
            guard let sub = item.submenu, let label = item.label else { return }
            let subMenu = try buildMenu(sub, isPopup: true)
            // 팝업으로 첨부. HMENU는 UINT_PTR로 재해석된다.
            let id = UINT_PTR(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(subMenu))))
            label.withUTF16Pointer { ptr in
                _ = AppendMenuW(parent, UINT(MF_STRING | MF_POPUP), id, ptr)
            }

        case .action:
            let label = decoratedLabel(for: item)
            let id = KSWin32MenuRegistry.shared.allocate(
                command: item.command, itemID: item.id)

            var flags: UINT = UINT(MF_STRING)
            if !item.enabled { flags |= UINT(MF_GRAYED) }
            if item.checked == true { flags |= UINT(MF_CHECKED) }

            label.withUTF16Pointer { ptr in
                _ = AppendMenuW(parent, flags, UINT_PTR(id), ptr)
            }
        }
    }

    /// Joins a menu label and accelerator with a tab so Win32 right-aligns
    /// the shortcut hint, e.g. `"New\tCtrl+N"`.
    private static func decoratedLabel(for item: KSMenuItem) -> String {
        guard let label = item.label else { return "" }
        guard let accel = item.accelerator, !accel.isEmpty else { return label }
        return "\(label)\t\(accel.replacingOccurrences(of: "CmdOrCtrl", with: "Ctrl"))"
    }
}

// MARK: - Window tracker

/// Records every top-level window the platform creates so the menu
/// backend can apply an app-wide menubar without reaching into private
/// state on `Win32App`.
@MainActor
internal final class KSWin32MainWindowTracker {
    static let shared = KSWin32MainWindowTracker()
    private var hwnds: Set<UInt> = []
    private init() {}

    func track(hwnd: HWND) {
        hwnds.insert(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd))))
    }
    func untrack(hwnd: HWND) {
        hwnds.remove(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd))))
    }
    func allWindowHWNDs() -> [HWND] {
        hwnds.compactMap { HWND(bitPattern: $0) }
    }
}
#endif
