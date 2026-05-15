import Foundation

/// 어떤 윈도우/플랫폼에 어떤 권한 묶음을 적용할지 결정하는 정책 단위.
///
/// Tauri 2의 `capabilities/*.json`에 대응한다. 한 capability는 1개 이상의
/// `KSPermission`을 식별자로 참조하고, 그 권한들이 활성화되는 윈도우 라벨
/// 집합을 지정한다.
public struct KSCapability: Codable, Sendable, Equatable {
    /// capability 식별자. 진단 메시지와 검증 보고서에 사용.
    public var identifier: String
    /// 사람이 읽을 수 있는 설명.
    public var description: String?
    /// 이 capability가 적용될 윈도우 라벨 목록.
    /// `["*"]`이면 모든 윈도우.
    /// 글롭 패턴 `"main-*"`도 지원한다 (끝에 `*` 하나).
    public var windows: [String]
    /// 참조할 `KSPermission.identifier` 목록.
    public var permissions: [String]
    /// 이 capability가 활성화되는 플랫폼 식별자(`"windows"`, `"macOS"`,
    /// `"linux"`, `"iOS"`, `"android"`). `nil`이면 모든 플랫폼.
    public var platforms: [String]?
    /// 로컬(앱 번들/ks:// 자산) 콘텐츠에서의 IPC 호출을 허용하는지 여부.
    /// 기본값 `true`. `false`이면 이 capability는 로컬 origin 호출과 매칭되지 않는다.
    public var local: Bool
    /// 원격(remote) origin 에서의 IPC 호출을 허용할 때 매칭에 사용할 URL
    /// 패턴 묶음. `nil` 이면 이 capability는 원격 origin과 매칭되지 않는다.
    public var remote: KSRemoteOriginConfig?

    public init(
        identifier: String,
        description: String? = nil,
        windows: [String] = ["*"],
        permissions: [String] = [],
        platforms: [String]? = nil,
        local: Bool = true,
        remote: KSRemoteOriginConfig? = nil
    ) {
        self.identifier = identifier
        self.description = description
        self.windows = windows
        self.permissions = permissions
        self.platforms = platforms
        self.local = local
        self.remote = remote
    }

    private enum CodingKeys: String, CodingKey {
        case identifier, description, windows, permissions, platforms, local, remote
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try c.decode(String.self, forKey: .identifier)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.windows = try c.decodeIfPresent([String].self, forKey: .windows) ?? ["*"]
        self.permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        self.platforms = try c.decodeIfPresent([String].self, forKey: .platforms)
        self.local = try c.decodeIfPresent(Bool.self, forKey: .local) ?? true
        self.remote = try c.decodeIfPresent(KSRemoteOriginConfig.self, forKey: .remote)
    }
}

extension KSCapability {
    /// 윈도우 라벨이 이 capability의 `windows` 목록에 매칭되는지 검사한다.
    public func matches(windowLabel: String) -> Bool {
        for pattern in windows {
            if pattern == "*" { return true }
            if pattern == windowLabel { return true }
            if pattern.hasSuffix("*") {
                let prefix = String(pattern.dropLast())
                if windowLabel.hasPrefix(prefix) { return true }
            }
        }
        return false
    }

    /// 주어진 플랫폼 식별자에서 이 capability가 활성화되는지 검사한다.
    public func matches(platform: String) -> Bool {
        guard let platforms else { return true }
        return platforms.contains(platform)
    }

    /// 주어진 origin이 이 capability의 매칭 정책을 만족하는지 검사한다.
    ///
    /// - `origin` 이 `nil` 이면 호출 컨텍스트가 알려지지 않은 것으로 간주하며,
    ///   `local == true` 일 때만 매칭된다.
    /// - `origin` 이 `"ks://"`, `"file://"`, `"https://app.kalsae"` 등 로컬
    ///   가상 호스트 origin이면 `local == true` 일 때 매칭된다.
    /// - 그 외 외부 origin은 `remote?.urls` 중 하나라도 매칭될 때 허용한다.
    public func matches(origin: String?) -> Bool {
        guard let origin else {
            return local
        }
        if Self.isLocalOrigin(origin) {
            return local
        }
        guard let remote else { return false }
        for pattern in remote.urls {
            if KSOriginMatcher.matches(pattern: pattern, origin: origin) {
                return true
            }
        }
        return false
    }

    /// 로컬 가상 호스트 / 파일 origin 판별. WebView가 `ks://` 또는
    /// `https://app.kalsae` 또는 `file://` 또는 `about:blank`을 띄울 때 사용.
    internal static func isLocalOrigin(_ origin: String) -> Bool {
        let lower = origin.lowercased()
        if lower.hasPrefix("ks://") { return true }
        if lower.hasPrefix("file://") { return true }
        if lower == "about:blank" { return true }
        if lower.hasPrefix("https://app.kalsae") { return true }
        return false
    }
}
