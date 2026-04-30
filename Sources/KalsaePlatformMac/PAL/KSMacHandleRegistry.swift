#if os(macOS)
internal import AppKit
public import KalsaeCore

/// Resolves a `KSWindowHandle` to a macOS `NSWindow`.
///
/// Used by every PAL backend (dialogs, menus, tray, shell) to find the
/// parent window that anchors a modal call. Mirrors `KSWin32HandleRegistry`
/// on the Windows side.
@MainActor
internal final class KSMacHandleRegistry {
    static let shared = KSMacHandleRegistry()

    private var byLabel: [String: KSMacWindow] = [:]
    private var byRawValue: [UInt64: KSMacWindow] = [:]

    private init() {}

    func register(label: String, rawValue: UInt64, window: KSMacWindow) {
        byLabel[label] = window
        byRawValue[rawValue] = window
    }

    func unregister(label: String) {
        guard let w = byLabel.removeValue(forKey: label) else { return }
        if let key = byRawValue.first(where: { $0.value === w })?.key {
            byRawValue.removeValue(forKey: key)
        }
    }

    func window(for handle: KSWindowHandle) -> KSMacWindow? {
        if let w = byLabel[handle.label] { return w }
        return byRawValue[handle.rawValue]
    }

    func handle(for label: String) -> KSWindowHandle? {
        guard let w = byLabel[label] else { return nil }
        return KSWindowHandle(
            label: label,
            rawValue: UInt64(UInt(bitPattern: ObjectIdentifier(w))))
    }

    func allWindows() -> [KSMacWindow] {
        Array(byLabel.values)
    }
}
#endif