/// `@KSCommand` 매크로가 명령에 부착하는 정적 메타데이터.
///
/// 런타임 게이팅(capability 평가)에는 사용되지 않으며,
/// CLI `CapabilityValidator`와 BindingsGenerator 같은 도구 계층이
/// 명령에 선언된 권한 식별자를 알아내기 위해 사용한다.
public struct KSCommandMetadata: Sendable, Equatable {
    /// `@KSCommand(permission: "fs:read")`로 선언된 권한 식별자.
    /// 선언되지 않은 경우 `nil`.
    public let permission: String?

    public init(permission: String?) {
        self.permission = permission
    }
}
