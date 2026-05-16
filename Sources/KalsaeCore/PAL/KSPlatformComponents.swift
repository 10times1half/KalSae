/// 플랫폼 백엔드 컴포넌트 다발(Aggregate).
///
/// `KSPlatform` 프로토콜이 노출하는 10개 백엔드 슬롯을 하나의 값 타입으로
/// 묶는다. 각 플랫폼 구현(`KSMacPlatform` 등)이 본 구조체와
/// `KSPlatformComponentsProvider` 프로토콜을 채택하면 10개의 public
/// store-through 프로퍼티를 자동으로 얻을 수 있어 보일러플레이트가 사라진다.
///
/// `var` 필드로 둔 이유는 부팅 도중 `autostart` / `deepLink`가 설정에 따라
/// 사후에 채워지는 플랫폼이 있기 때문이다. 모든 백엔드 프로토콜은 `Sendable`
/// 이므로 본 구조체 또한 자동으로 `Sendable`이다.
public struct KSPlatformComponents: Sendable {
    public var windows: any KSWindowBackend
    public var dialogs: any KSDialogBackend
    public var menus: any KSMenuBackend
    public var notifications: any KSNotificationBackend
    public var tray: (any KSTrayBackend)?
    public var shell: (any KSShellBackend)?
    public var clipboard: (any KSClipboardBackend)?
    public var accelerators: (any KSAcceleratorBackend)?
    public var autostart: (any KSAutostartBackend)?
    public var deepLink: (any KSDeepLinkBackend)?
    public var credentials: (any KSCredentialBackend)?

    public init(
        windows: any KSWindowBackend,
        dialogs: any KSDialogBackend,
        menus: any KSMenuBackend,
        notifications: any KSNotificationBackend,
        tray: (any KSTrayBackend)? = nil,
        shell: (any KSShellBackend)? = nil,
        clipboard: (any KSClipboardBackend)? = nil,
        accelerators: (any KSAcceleratorBackend)? = nil,
        autostart: (any KSAutostartBackend)? = nil,
        deepLink: (any KSDeepLinkBackend)? = nil,
        credentials: (any KSCredentialBackend)? = nil
    ) {
        self.windows = windows
        self.dialogs = dialogs
        self.menus = menus
        self.notifications = notifications
        self.tray = tray
        self.shell = shell
        self.clipboard = clipboard
        self.accelerators = accelerators
        self.autostart = autostart
        self.deepLink = deepLink
        self.credentials = credentials
    }
}

/// `KSPlatform`의 10개 백엔드 프로퍼티를 `components`에 위임하기 위한
/// 헬퍼 프로토콜. 플랫폼 구현이 본 프로토콜을 채택하면 10개의 public
/// 계산 프로퍼티를 직접 작성할 필요가 없다.
public protocol KSPlatformComponentsProvider: KSPlatform {
    /// 이 플랫폼이 노출하는 백엔드 컴포넌트.
    var components: KSPlatformComponents { get }
}

extension KSPlatformComponentsProvider {
    public var windows: any KSWindowBackend { components.windows }
    public var dialogs: any KSDialogBackend { components.dialogs }
    public var menus: any KSMenuBackend { components.menus }
    public var notifications: any KSNotificationBackend { components.notifications }
    public var tray: (any KSTrayBackend)? { components.tray }
    public var shell: (any KSShellBackend)? { components.shell }
    public var clipboard: (any KSClipboardBackend)? { components.clipboard }
    public var accelerators: (any KSAcceleratorBackend)? { components.accelerators }
    public var autostart: (any KSAutostartBackend)? { components.autostart }
    public var deepLink: (any KSDeepLinkBackend)? { components.deepLink }
    public var credentials: (any KSCredentialBackend)? { components.credentials }
}
