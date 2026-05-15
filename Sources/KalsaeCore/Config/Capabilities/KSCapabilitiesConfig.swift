import Foundation

/// `kalsae.json`의 최상위 `capabilities` 섹션.
///
/// ```json
/// {
///   "capabilities": {
///     "permissions": [
///       { "identifier": "fs:allow-read", "commandsAllow": ["fs.read*"] },
///       { "identifier": "shell:allow-open", "commandsAllow": ["__ks.shell.openExternal"] }
///     ],
///     "capabilities": [
///       {
///         "identifier": "main",
///         "windows": ["main"],
///         "permissions": ["fs:allow-read", "shell:allow-open"]
///       }
///     ]
///   }
/// }
/// ```
///
/// 미지정 시 Kalsae는 기존 `security.commandAllowlist` / `security.fs` 등
/// 레거시 정책을 그대로 사용한다 (호환성 보장).
public struct KSCapabilitiesConfig: Codable, Sendable, Equatable {
    /// 권한 카탈로그. 각 권한은 고유 `identifier`를 가져야 한다.
    public var permissions: [KSPermission]
    /// 적용 정책. 각 capability는 고유 `identifier`를 가져야 한다.
    public var capabilities: [KSCapability]

    public init(
        permissions: [KSPermission] = [],
        capabilities: [KSCapability] = []
    ) {
        self.permissions = permissions
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey {
        case permissions, capabilities
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.permissions = try c.decodeIfPresent([KSPermission].self, forKey: .permissions) ?? []
        self.capabilities = try c.decodeIfPresent([KSCapability].self, forKey: .capabilities) ?? []
    }

    /// `permissions` 또는 `capabilities`가 비어 있지 않으면 "활성"으로 간주된다.
    public var isEmpty: Bool {
        permissions.isEmpty && capabilities.isEmpty
    }
}
