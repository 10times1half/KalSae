import Foundation

/// `KSPermission`에 부착되는 선언적 스코프 묶음.
///
/// **v1에서는 선언적 메타데이터로 사용된다.** 실제 IPC 인자 검증은
/// 기존 `security.fs` / `security.http` / `security.shell` /
/// `security.navigation` / `security.notifications`의 레거시 스코프
/// 검증기가 그대로 수행한다. 이 타입은 다음 두 가지 용도이다:
///
/// 1. **문서/검증 자동화**: `kalsae build` 시 CLI가 capability에서 사용된
///    스코프를 수집해 "이 커맨드는 어떤 경로/URL/스킴에 접근 가능한가"를
///    리포트한다.
/// 2. **v1.1 확장점**: 이후 evaluator가 인자 검증까지 끌어올릴 때
///    추가 코드 변경 없이 그대로 사용 가능하다.
public struct KSPermissionScope: Codable, Sendable, Equatable {
    /// 파일 시스템 접근 범위.
    public var fs: KSFSScope?
    /// HTTP fetch 허용 범위.
    public var http: KSHTTPScope?
    /// 셸 명령 권한 범위.
    public var shell: KSShellScope?
    /// 내비게이션 허용 범위.
    public var navigation: KSNavigationScope?
    /// 알림 권한 범위.
    public var notifications: KSNotificationScope?

    public init(
        fs: KSFSScope? = nil,
        http: KSHTTPScope? = nil,
        shell: KSShellScope? = nil,
        navigation: KSNavigationScope? = nil,
        notifications: KSNotificationScope? = nil
    ) {
        self.fs = fs
        self.http = http
        self.shell = shell
        self.navigation = navigation
        self.notifications = notifications
    }

    private enum CodingKeys: String, CodingKey {
        case fs, http, shell, navigation, notifications
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fs = try c.decodeIfPresent(KSFSScope.self, forKey: .fs)
        self.http = try c.decodeIfPresent(KSHTTPScope.self, forKey: .http)
        self.shell = try c.decodeIfPresent(KSShellScope.self, forKey: .shell)
        self.navigation = try c.decodeIfPresent(KSNavigationScope.self, forKey: .navigation)
        self.notifications = try c.decodeIfPresent(KSNotificationScope.self, forKey: .notifications)
    }

    /// 이 스코프 객체에 실질적인 필드가 하나라도 설정되어 있는지 여부.
    public var isEmpty: Bool {
        fs == nil && http == nil && shell == nil && navigation == nil && notifications == nil
    }
}
