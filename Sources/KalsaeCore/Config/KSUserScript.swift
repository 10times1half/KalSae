/// 사용자가 모든 navigation(외부 origin 포함)에 주입하는 JavaScript 정의.
///
/// Tauri v2의 `initialization_script`에 대응하는 표면이다. `kalsae.json`의
/// `security.userScripts.scripts`에 선언하거나, 런타임에 `KSApp.addUserScript`로
/// 등록할 수 있다. 모든 등록은 `security.userScripts.allowOrigins` 화이트리스트를
/// 통과해야 한다(default-deny).
///
/// 메인 월드에서 실행되며 페이지 JS와 동일 컨텍스트를 공유한다.
public import Foundation

public struct KSUserScript: Sendable, Equatable, Codable {
    /// 제거 식별자. 비어 있으면 `KSApp.addUserScript` 호출 시점에 UUID로 자동 채워진다.
    public var id: String

    /// 인라인 JavaScript 본문. `path`와 정확히 하나만 지정해야 한다.
    public var source: String?

    /// resourceRoot 상대 경로. Config 선언 시 권장. 디렉터리 탈출(`..`) 금지.
    public var path: String?

    /// 주입 시점.
    public var injectionTime: InjectionTime

    /// `true`이면 최상위 프레임에만 주입. iframe 포함하려면 `false`(기본값).
    public var forMainFrameOnly: Bool

    /// 이 스크립트가 활성화될 origin 패턴. `KSHTTPScope`와 동일한 glob 문법.
    /// 예: `"https://example.org"`, `"https://*.example.org"`, `"https://example.org/app/**"`.
    public var origins: [String]

    public enum InjectionTime: String, Codable, Sendable, Equatable {
        case documentStart
        case documentEnd
    }

    public init(
        id: String = "",
        source: String? = nil,
        path: String? = nil,
        injectionTime: InjectionTime = .documentStart,
        forMainFrameOnly: Bool = false,
        origins: [String] = []
    ) {
        self.id = id
        self.source = source
        self.path = path
        self.injectionTime = injectionTime
        self.forMainFrameOnly = forMainFrameOnly
        self.origins = origins
    }

    private enum CodingKeys: String, CodingKey {
        case id, source, path, injectionTime, forMainFrameOnly, origins
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.source = try c.decodeIfPresent(String.self, forKey: .source)
        self.path = try c.decodeIfPresent(String.self, forKey: .path)
        self.injectionTime =
            try c.decodeIfPresent(InjectionTime.self, forKey: .injectionTime) ?? .documentStart
        self.forMainFrameOnly =
            try c.decodeIfPresent(Bool.self, forKey: .forMainFrameOnly) ?? false
        self.origins = try c.decodeIfPresent([String].self, forKey: .origins) ?? []
    }
}

/// `security.userScripts` 권한 범위. **default-deny**.
///
/// `allowOrigins`가 비어 있으면 어떤 사용자 스크립트도 등록할 수 없다(런타임 API와
/// Config 선언 모두 거부됨). `scripts[i].origins`의 모든 항목은 `allowOrigins`의
/// 부분집합이어야 한다.
public struct KSUserScriptsScope: Codable, Sendable, Equatable {
    /// 사용자 스크립트가 실행될 수 있는 origin glob 화이트리스트.
    public var allowOrigins: [String]

    /// 부팅 시 자동으로 등록되는 선언 스크립트.
    public var scripts: [KSUserScript]

    public init(allowOrigins: [String] = [], scripts: [KSUserScript] = []) {
        self.allowOrigins = allowOrigins
        self.scripts = scripts
    }

    private enum CodingKeys: String, CodingKey {
        case allowOrigins, scripts
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.allowOrigins =
            try c.decodeIfPresent([String].self, forKey: .allowOrigins) ?? []
        self.scripts =
            try c.decodeIfPresent([KSUserScript].self, forKey: .scripts) ?? []
    }

    /// 주어진 origin 패턴이 `allowOrigins`의 부분집합인지 검사한다.
    /// 단순 문자열 동치 매칭이며(공백 trim, 대소문자 무시), glob 포함관계를
    /// 일반화하지는 않는다. 호스트 앱은 동일한 패턴 문자열을 양쪽에 적어야 한다.
    public func permits(originPattern: String) -> Bool {
        let needle = originPattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty { return false }
        return allowOrigins.contains { entry in
            entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == needle
        }
    }

    /// 주어진 URL이 `allowOrigins` 중 어느 패턴이라도 매칭하면 `true`.
    /// `KSHTTPScope.permits(urlString:)`을 재사용한다.
    public func matchesURL(_ urlString: String) -> Bool {
        if allowOrigins.isEmpty { return false }
        let stub = KSHTTPScope(allow: allowOrigins)
        return stub.permits(urlString: urlString)
    }
}
