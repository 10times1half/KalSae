/// 앱 메뉴(macOS), 창 메뉴(Windows), 트레이 메뉴, 컨텍스트 메뉴에 사용되는
/// 선언적 메뉴 트리.
import Foundation

/// 단일 메뉴 항목.
/// 리프 액션, 서브메뉴, 구분선 중 하나다.

/// 알림 런타임 설정.
public struct KSMenuConfig: Codable, Sendable, Equatable {
    /// 앱 전역 메뉴 트리.
    public var appMenu: [KSMenuItem]?
    /// 창별 메뉴 트리.
    public var windowMenu: [KSMenuItem]?

    public init(
        appMenu: [KSMenuItem]? = nil,
        windowMenu: [KSMenuItem]? = nil
    ) {
        self.appMenu = appMenu
        self.windowMenu = windowMenu
    }
}
public struct KSMenuItem: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case action
        case submenu
        case separator
    }

    /// 메뉴 항목 종류.
    public var kind: Kind
    /// 항목의 안정적인 내부 식별자.
    public var id: String?
    /// 사용자에게 보이는 메뉴 레이블.
    public var label: String?
    /// 크로스플랫폼 표기법의 가속키. 예: `"CmdOrCtrl+Shift+N"`.
    public var accelerator: String?
    /// 현재 항목이 선택 가능 상태인지 여부.
    public var enabled: Bool
    /// 체크형 메뉴에서 현재 체크 상태.
    public var checked: Bool?
    /// `kind == .submenu`일 때 포함되는 하위 항목들.
    public var submenu: [KSMenuItem]?
    /// 이 항목이 클릭될 때 실행되는 `@KSCommand` ID(또는 이벤트 이름).
    public var command: String?

    public init(
        kind: Kind,
        id: String? = nil,
        label: String? = nil,
        accelerator: String? = nil,
        enabled: Bool = true,
        checked: Bool? = nil,
        submenu: [KSMenuItem]? = nil,
        command: String? = nil
    ) {
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

    public static func action(
        id: String,
        label: String,
        accelerator: String? = nil,
        command: String? = nil
    ) -> KSMenuItem {
        KSMenuItem(
            kind: .action,
            id: id,
            label: label,
            accelerator: accelerator,
            command: command)
    }

    public static func submenu(
        id: String,
        label: String,
        items: [KSMenuItem]
    ) -> KSMenuItem {
        KSMenuItem(
            kind: .submenu,
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
public struct KSNotificationConfig: Codable, Sendable, Equatable {
    /// Windows에서 앱 식별성이 있는 토스트를 표시할 때 필요하다.
    /// `nil`이면 `KSAppInfo.identifier`로 폴백한다.
    public var appUserModelID: String?
    /// 프로젝트 루트 기준 기본 아이콘 경로.
    public var defaultIcon: String?

    public init(appUserModelID: String? = nil, defaultIcon: String? = nil) {
        self.appUserModelID = appUserModelID
        self.defaultIcon = defaultIcon
    }
}
