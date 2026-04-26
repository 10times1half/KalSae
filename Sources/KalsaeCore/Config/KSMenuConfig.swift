import Foundation

/// Declarative menu tree used for the app menu (macOS), window menu
/// (Windows), tray menu, and context menus.
public struct KSMenuConfig: Codable, Sendable, Equatable {
    public var appMenu: [KSMenuItem]?
    public var windowMenu: [KSMenuItem]?

    public init(appMenu: [KSMenuItem]? = nil,
                windowMenu: [KSMenuItem]? = nil) {
        self.appMenu = appMenu
        self.windowMenu = windowMenu
    }
}

/// A single menu item. Either a leaf action, a submenu, or a separator.
public struct KSMenuItem: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case action
        case submenu
        case separator
    }

    public var kind: Kind
    public var id: String?
    public var label: String?
    /// Accelerator in cross-platform notation, e.g. `"CmdOrCtrl+Shift+N"`.
    public var accelerator: String?
    public var enabled: Bool
    public var checked: Bool?
    public var submenu: [KSMenuItem]?
    /// `@KSCommand` id (or an event name) fired when this item is clicked.
    public var command: String?

    public init(kind: Kind,
                id: String? = nil,
                label: String? = nil,
                accelerator: String? = nil,
                enabled: Bool = true,
                checked: Bool? = nil,
                submenu: [KSMenuItem]? = nil,
                command: String? = nil) {
        self.kind = kind
        self.id = id
        self.label = label
        self.accelerator = accelerator
        self.enabled = enabled
        self.checked = checked
        self.submenu = submenu
        self.command = command
    }

    public static func separator() -> KSMenuItem {
        KSMenuItem(kind: .separator)
    }

    public static func action(id: String,
                              label: String,
                              accelerator: String? = nil,
                              command: String? = nil) -> KSMenuItem {
        KSMenuItem(kind: .action,
                   id: id,
                   label: label,
                   accelerator: accelerator,
                   command: command)
    }

    public static func submenu(id: String,
                               label: String,
                               items: [KSMenuItem]) -> KSMenuItem {
        KSMenuItem(kind: .submenu,
                   id: id,
                   label: label,
                   submenu: items)
    }

    // 선택 필드를 모든 `Optional`로 선언하지 않고도 JSON에서 생략할 수
    // 있도록 커스텀 디코딩을 제공한다. `enabled` 기본값은 `true` —
    // 최소 메뉴 트리를 `Kalsae.json`에서 볼 때 독자가 기대하는 동작을
    // 그대로 따른다.
    private enum CodingKeys: String, CodingKey {
        case kind, id, label, accelerator, enabled, checked, submenu, command
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.accelerator = try c.decodeIfPresent(String.self, forKey: .accelerator)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.checked = try c.decodeIfPresent(Bool.self, forKey: .checked)
        self.submenu = try c.decodeIfPresent([KSMenuItem].self, forKey: .submenu)
        self.command = try c.decodeIfPresent(String.self, forKey: .command)
    }
}

/// Notification runtime configuration.
public struct KSNotificationConfig: Codable, Sendable, Equatable {
    /// Required on Windows to display toasts with app identity. Falls back
    /// to `KSAppInfo.identifier` when `nil`.
    public var appUserModelID: String?
    /// Default icon, relative to project root.
    public var defaultIcon: String?

    public init(appUserModelID: String? = nil, defaultIcon: String? = nil) {
        self.appUserModelID = appUserModelID
        self.defaultIcon = defaultIcon
    }
}
