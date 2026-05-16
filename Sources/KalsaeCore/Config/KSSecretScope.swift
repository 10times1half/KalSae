/// `__ks.secret.*` 명령군에 대한 권한 범위.
///
/// **기본 거부**다. 빈 값으로 두면 `__ks.secret.{set,get,delete,list}`는
/// 모든 호출을 `KSError(.commandNotAllowed)`로 거부한다. 앱은 신뢰하는
/// `service` 접두사를 명시적으로 추가해야 한다.
///
/// `allowedServices`는 호스트가 자동으로 적용하는 bundleId prefix
/// **뒤의** 부분과 비교한다. 예를 들어 `app.identifier`가 `"dev.x.app"`이고
/// `allowedServices = ["github"]`이면 JS의 `service: "github"` 호출은
/// 내부적으로 `"dev.x.app.github"`로 정규화된 뒤 허용된다.
import Foundation

public struct KSSecretScope: Codable, Sendable, Equatable {
    /// 마스터 게이트. `false`(기본값)이면 `__ks.secret.*` 호출 전체가 거부된다.
    public var enabled: Bool

    /// 허용되는 service 이름(bundleId prefix 제외). 빈 배열이면 어떤 service도
    /// 허용되지 않는다(즉, `enabled=true`만으로는 부족하며 명시적 화이트리스트가
    /// 필요하다). 와일드카드 `"*"` 한 항목으로 모든 service를 허용할 수 있다.
    public var allowedServices: [String]

    /// 단일 시크릿 본문의 최대 바이트 수. 기본 64 KiB.
    /// 이를 초과하는 `set` 호출은 `invalidArgument`로 거부된다.
    public var maxSecretBytes: Int

    /// `__ks.secret.list` 허용 여부.
    public var allowList: Bool

    /// `__ks.secret.delete` 허용 여부.
    public var allowDelete: Bool

    public init(
        enabled: Bool = false,
        allowedServices: [String] = [],
        maxSecretBytes: Int = 64 * 1024,
        allowList: Bool = true,
        allowDelete: Bool = true
    ) {
        self.enabled = enabled
        self.allowedServices = allowedServices
        self.maxSecretBytes = maxSecretBytes
        self.allowList = allowList
        self.allowDelete = allowDelete
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, allowedServices, maxSecretBytes, allowList, allowDelete
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.allowedServices = try c.decodeIfPresent([String].self, forKey: .allowedServices) ?? []
        self.maxSecretBytes = try c.decodeIfPresent(Int.self, forKey: .maxSecretBytes) ?? (64 * 1024)
        self.allowList = try c.decodeIfPresent(Bool.self, forKey: .allowList) ?? true
        self.allowDelete = try c.decodeIfPresent(Bool.self, forKey: .allowDelete) ?? true
    }

    /// `service`가 이 범위에 의해 허용되면 `true`.
    /// 비교는 대소문자를 구분한다(시크릿 키 일관성을 위해).
    public func permits(service: String) -> Bool {
        guard enabled else { return false }
        for pattern in allowedServices {
            if pattern == "*" { return true }
            if pattern == service { return true }
        }
        return false
    }
}
