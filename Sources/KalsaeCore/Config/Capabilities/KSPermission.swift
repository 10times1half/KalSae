import Foundation

/// 단일 권한(Permission) 단위.
///
/// 권한은 "어떤 IPC 커맨드를 호출할 수 있는가"를 정의하는 최소 단위이며,
/// `KSCapability`에 의해 윈도우/플랫폼별로 묶여 적용된다.
///
/// `commandsDeny`는 `commandsAllow`보다 우선한다.
///
/// 패턴 규칙:
/// - 정확한 이름: `"app.greet"`
/// - 접두 글롭: `"fs.*"`, `"__ks.shell.*"` — 와일드카드는 끝에 `*` 하나만.
/// - 전체 와일드카드: `"*"` (CLI 검증기가 경고를 띄움).
public struct KSPermission: Codable, Sendable, Equatable {
    /// 권한 식별자. 플러그인이 제공하는 경우 `<namespace>:<name>` 형식을 권장한다.
    public var identifier: String
    /// 사람이 읽을 수 있는 설명. 자동 생성된 문서/검증 보고서에 사용.
    public var description: String?
    /// 이 권한이 허용하는 커맨드 패턴 목록.
    public var commandsAllow: [String]
    /// 이 권한이 거부하는 커맨드 패턴 목록. `commandsAllow`보다 우선한다.
    public var commandsDeny: [String]
    /// 선택적 스코프(파일/HTTP/셸/내비게이션/알림). v1에서는 선언적 메타이며,
    /// 실제 인자 검증은 기존 `security.fs` 등 레거시 스코프 검증기가 수행한다.
    public var scope: KSPermissionScope?

    public init(
        identifier: String,
        description: String? = nil,
        commandsAllow: [String] = [],
        commandsDeny: [String] = [],
        scope: KSPermissionScope? = nil
    ) {
        self.identifier = identifier
        self.description = description
        self.commandsAllow = commandsAllow
        self.commandsDeny = commandsDeny
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, description, commandsAllow, commandsDeny, scope
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try c.decode(String.self, forKey: .identifier)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.commandsAllow = try c.decodeIfPresent([String].self, forKey: .commandsAllow) ?? []
        self.commandsDeny = try c.decodeIfPresent([String].self, forKey: .commandsDeny) ?? []
        self.scope = try c.decodeIfPresent(KSPermissionScope.self, forKey: .scope)
    }
}

extension KSPermission {
    /// 주어진 커맨드 이름이 이 권한에 의해 결정되는 방식을 반환한다.
    /// 어느 패턴에도 매칭되지 않으면 `.unspecified`.
    public func decision(for command: String) -> KSPermissionDecision {
        if Self.anyMatch(command, in: commandsDeny) { return .deny }
        if Self.anyMatch(command, in: commandsAllow) { return .allow }
        return .unspecified
    }

    /// 패턴이 커맨드를 매칭하는지 검사한다.
    /// 지원 패턴: 정확 일치, `prefix.*`, `*`.
    public static func matches(_ command: String, pattern: String) -> Bool {
        if pattern == "*" { return true }
        if pattern == command { return true }
        if pattern.hasSuffix(".*") {
            let prefix = String(pattern.dropLast(2))
            return command == prefix || command.hasPrefix(prefix + ".")
        }
        if pattern.hasSuffix("*") {
            return command.hasPrefix(String(pattern.dropLast()))
        }
        return false
    }

    private static func anyMatch(_ command: String, in patterns: [String]) -> Bool {
        for p in patterns where matches(command, pattern: p) {
            return true
        }
        return false
    }
}

/// 권한 패턴 매칭 결과.
public enum KSPermissionDecision: Sendable, Equatable {
    /// 명시적으로 허용.
    case allow
    /// 명시적으로 거부.
    case deny
    /// 이 권한은 해당 커맨드에 대해 의견을 갖지 않는다.
    case unspecified
}
