/// IPC 정책 평가 결과.
public enum KSPolicyDecision: Sendable, Equatable {
    /// 호출이 허용됨. `capability`는 매칭된 capability 식별자(진단용).
    case allow(capability: String?)
    /// 호출이 거부됨.
    case deny(reason: KSPolicyDenyReason)
}

/// 거부 사유.
public enum KSPolicyDenyReason: Sendable, Equatable {
    /// 어떤 capability도 이 호출에 매칭되지 않음.
    case noMatchingCapability
    /// 매칭된 capability 안에 명시적 deny가 있음.
    case explicitDeny(capability: String, permission: String)
    /// 매칭된 capability는 있으나 이 커맨드를 허용하는 권한이 없음.
    case notInAllowlist(capability: String)
    /// 참조한 권한 식별자가 카탈로그에 없음 (설정 오류).
    case unknownPermission(capability: String, permission: String)

    /// 사람이 읽을 수 있는 사유 문자열. JS 측에 그대로 전달된다.
    public var message: String {
        switch self {
        case .noMatchingCapability:
            return "no capability matches this window"
        case .explicitDeny(let cap, let perm):
            return "explicit deny in capability '\(cap)' via permission '\(perm)'"
        case .notInAllowlist(let cap):
            return "command not allowed by capability '\(cap)'"
        case .unknownPermission(let cap, let perm):
            return "capability '\(cap)' references unknown permission '\(perm)'"
        }
    }

    /// 진단 메타에 채워질 capability 식별자(있으면).
    public var capabilityIdentifier: String? {
        switch self {
        case .noMatchingCapability: return nil
        case .explicitDeny(let cap, _): return cap
        case .notInAllowlist(let cap): return cap
        case .unknownPermission(let cap, _): return cap
        }
    }
}
