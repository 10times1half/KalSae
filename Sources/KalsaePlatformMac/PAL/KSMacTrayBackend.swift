#if os(macOS)
    internal import AppKit
    public import KalsaeCore
    public import Foundation

    /// macOS implementation of `KSTrayBackend` using NSStatusBar.
    @MainActor
    public final class KSMacTrayBackend: KSTrayBackend {
        private var statusItem: NSStatusItem?
        private var menu: NSMenu?
        private var onLeftClickCommand: String?

        public nonisolated init() {}

        public func install(_ config: KSTrayConfig) async throws(KSError) {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let btn = item.button {
                if let iconPath = config.icon, !iconPath.isEmpty {
                    let img: NSImage
                    if let nsImg = NSImage(contentsOfFile: iconPath) {
                        img = nsImg
                        img.size = NSSize(width: 18, height: 18)
                    } else {
                        img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in true }
                    }
                    btn.image = img
                } else {
                    btn.title = config.tooltip ?? ""
                }
                btn.toolTip = config.tooltip
                btn.target = self
                btn.action = #selector(statusItemClicked)
                btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }

            if let menuItems = config.menu, !menuItems.isEmpty {
                let nsMenu = KSMacMenuBackend.buildMenuInternal(menuItems)
                item.menu = nsMenu
            }

            self.statusItem = item
            self.onLeftClickCommand = config.onLeftClick
        }

        public func setTooltip(_ tooltip: String) async throws(KSError) {
            statusItem?.button?.toolTip = tooltip
        }

        public func setMenu(_ items: [KSMenuItem]) async throws(KSError) {
            let nsMenu = KSMacMenuBackend.buildMenuInternal(items)
            statusItem?.menu = nsMenu
        }

        public func remove() async {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
        }

        @objc private func statusItemClicked() {
            guard let current = NSApp.currentEvent else { return }
            if current.type == .leftMouseUp, let cmd = onLeftClickCommand {
                KSMacCommandRouter.shared.dispatch(command: cmd, itemID: nil)
            }
        }
    }

    // Expose internal buildMenu for tray usage.
    extension KSMacMenuBackend {
        @MainActor
        static func buildMenuInternal(_ items: [KSMenuItem]) -> NSMenu {
            let menu = NSMenu()
            for item in items {
                switch item.kind {
                case .separator:
                    menu.addItem(.separator())
                case .submenu:
                    let sub = NSMenuItem()
                    sub.title = item.label ?? ""
                    sub.submenu = buildMenuInternal(item.submenu ?? [])
                    menu.addItem(sub)
                case .action:
                    let mi = NSMenuItem()
                    mi.title = item.label ?? ""
                    mi.isEnabled = item.enabled
                    mi.state = item.checked == true ? .on : .off
                    if let key = item.accelerator, !key.isEmpty {
                        let tokens = key.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
                        if let last = tokens.last {
                            mi.keyEquivalent =
                                last.lowercased() == "esc" ? "\u{1b}" : (last.count == 1 ? last.lowercased() : "")
                        }
                    }
                    mi.action = #selector(KSMacMenuTarget.invoke(_:))
                    mi.target = KSMacMenuTarget.shared
                    mi.representedObject = item.command
                    menu.addItem(mi)
                }
            }
            return menu
        }
    }
#endif
