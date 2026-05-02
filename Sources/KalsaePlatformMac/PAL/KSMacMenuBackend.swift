#if os(macOS)
    internal import AppKit
    public import KalsaeCore
    public import Foundation

    /// `KSMenuBackend`의 macOS 구현체.
    public struct KSMacMenuBackend: KSMenuBackend, Sendable {
        public init() {}

        public func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) {
            await MainActor.run {
                let menu = buildMenu(items)
                NSApplication.shared.mainMenu = menu
            }
        }

        public func installWindowMenu(
            _ handle: KSWindowHandle,
            items: [KSMenuItem]
        ) async throws(KSError) {
            // macOS는 일반적으로 app-wide 메뉴를 사용하므로, 윈도우별 메뉴는
            // 해당 윈도우가 키 윈도우일 때만 보이도록 대체 구현.
            try await installAppMenu(items)
        }

        public func showContextMenu(
            _ items: [KSMenuItem],
            at point: KSPoint,
            in handle: KSWindowHandle?
        ) async throws(KSError) {
            await MainActor.run {
                let menu = buildMenu(items)
                let nsPoint = NSPoint(x: CGFloat(point.x), y: CGFloat(point.y))
                let nsWindow =
                    handle.flatMap { KSMacHandleRegistry.shared.window(for: $0)?.nsWindow }
                    ?? NSApplication.shared.keyWindow
                let view = nsWindow?.contentView
                view.flatMap {
                    // 메뉴를 컨텍스트 메뉴로 팝업.
                    let menuItem = NSMenuItem()
                    menuItem.submenu = menu
                    NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSEvent(), for: $0)
                }
            }
        }

        // MARK: - Menu construction

        @MainActor
        private func buildMenu(_ items: [KSMenuItem]) -> NSMenu {
            let menu = NSMenu()
            for item in items {
                menu.addItem(buildItem(item))
            }
            return menu
        }

        @MainActor
        private func buildItem(_ item: KSMenuItem) -> NSMenuItem {
            switch item.kind {
            case .separator:
                return .separator()

            case .submenu:
                let sub = NSMenuItem()
                sub.title = item.label ?? ""
                sub.submenu = buildMenu(item.submenu ?? [])
                return sub

            case .action:
                let mi = NSMenuItem()
                mi.title = item.label ?? ""
                mi.isEnabled = item.enabled
                mi.state = item.checked == true ? .on : .off
                if let key = item.accelerator, !key.isEmpty {
                    mi.keyEquivalent = resolveKeyEquivalent(key)
                    mi.keyEquivalentModifierMask = resolveModifierFlags(key)
                }
                mi.action = #selector(KSMacMenuTarget.invoke(_:))
                mi.target = KSMacMenuTarget.shared
                mi.representedObject = item.command
                return mi
            }
        }

        private func resolveKeyEquivalent(_ accel: String) -> String {
            // Accelerator 파싱: 마지막 토큰이 키.
            let tokens = accel.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let last = tokens.last else { return "" }
            switch last.lowercased() {
            case "esc", "escape": return "\u{1b}"
            case "enter", "return": return "\r"
            case "tab": return "\t"
            case "backspace", "back": return "\u{8}"
            case "delete", "del": return "\u{7f}"
            case "space": return " "
            default:
                if last.count == 1 { return last.lowercased() }
                return ""
            }
        }

        private func resolveModifierFlags(_ accel: String) -> NSEvent.ModifierFlags {
            let lower = accel.lowercased()
            var flags: NSEvent.ModifierFlags = []
            if lower.contains("cmdorctrl") || lower.contains("cmd") || lower.contains("command")
                || lower.contains("super") || lower.contains("meta")
            {
                flags.insert(.command)
            }
            if lower.contains("shift") { flags.insert(.shift) }
            if lower.contains("alt") || lower.contains("option") { flags.insert(.option) }
            if lower.contains("ctrl") || lower.contains("control") { flags.insert(.control) }
            return flags
        }
    }

    /// Target object for NSMenuItem actions. Dispatches to KSWindowsCommandRouter equivalent.
    @MainActor
    internal final class KSMacMenuTarget: NSObject {
        static let shared = KSMacMenuTarget()

        @objc func invoke(_ sender: NSMenuItem) {
            guard let command = sender.representedObject as? String else { return }
            KSMacCommandRouter.shared.dispatch(command: command, itemID: nil)
        }
    }

    /// Routes menu clicks back to subscribers.
    @MainActor
    public final class KSMacCommandRouter {
        public static let shared = KSMacCommandRouter()

        public typealias Sink = @MainActor (_ command: String, _ itemID: String?) -> Void
        private var sinks: [Sink] = []

        private init() {}

        public func subscribe(_ sink: @escaping Sink) { sinks.append(sink) }
        public func clear() { sinks.removeAll() }

        internal func dispatch(command: String, itemID: String?) {
            for sink in sinks { sink(command, itemID) }
        }
    }
#endif
