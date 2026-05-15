/// `Kalsae.json`의 루트 스키마.
///
/// 참조 문서는 `Examples/Kalsae.sample.json`을 참고하라.
import Foundation

// MARK: - 앱 메타데이터

// MARK: - 빌드 / 개발 서버

public struct KSConfig: Codable, Sendable, Equatable {
    /// 앱 이름, 버전, 식별자 등 기본 메타데이터.
    public var app: KSAppInfo
    /// 프론트엔드 산출물 경로와 개발 서버 연결 정보.
    public var build: KSBuildConfig
    /// 부팅 시 만들 창 목록.
    public var windows: [KSWindowConfig]
    /// IPC, 파일시스템, 셸, 네트워크 접근 등을 제어하는 보안 정책.
    public var security: KSSecurityConfig
    /// 선택적 시스템 트레이 설정.
    public var tray: KSTrayConfig?
    /// 선택적 앱/창 메뉴 설정.
    public var menu: KSMenuConfig?
    /// 선택적 알림 기본 설정.
    public var notifications: KSNotificationConfig?
    /// 선택적 자동 시작 설정.
    public var autostart: KSAutostartConfig?
    /// 선택적 딥링크/커스텀 URL 스킴 설정.
    public var deepLink: KSDeepLinkConfig?
    /// 선택적 스토어 배포 메타데이터 (RFC-008).
    /// 생략 시 `KSDistributionConfig.default` (`target = .developer`).
    public var distribution: KSDistributionConfig
    /// 선택적 OS 권한 요구사항 (RFC-008).
    /// 생략 시 모든 권한 거부 (`KSPermissionsConfig.denied`).
    public var permissions: KSPermissionsConfig
    /// 선택적 Tauri 스타일 capability/permission 정책 (v1).
    ///
    /// `nil` 또는 빈 값이면 기존 `security.commandAllowlist` / scope
    /// 레거시 정책이 그대로 적용된다. 설정되어 있으면 capability
    /// 평가기가 우선하며, 레거시 필드 존재 시 경고가 로그되는 후
    /// 자동 다단 합성된다.
    public var capabilities: KSCapabilitiesConfig?

    public init(
        app: KSAppInfo,
        build: KSBuildConfig,
        windows: [KSWindowConfig],
        security: KSSecurityConfig = .default,
        tray: KSTrayConfig? = nil,
        menu: KSMenuConfig? = nil,
        notifications: KSNotificationConfig? = nil,
        autostart: KSAutostartConfig? = nil,
        deepLink: KSDeepLinkConfig? = nil,
        distribution: KSDistributionConfig = .default,
        permissions: KSPermissionsConfig = .denied,
        capabilities: KSCapabilitiesConfig? = nil
    ) {
        self.app = app
        self.build = build
        self.windows = windows
        self.security = security
        self.tray = tray
        self.menu = menu
        self.notifications = notifications
        self.autostart = autostart
        self.deepLink = deepLink
        self.distribution = distribution
        self.permissions = permissions
        self.capabilities = capabilities
    }

    // `security` 등 필수가 아닌 섹션은 JSON에서 생략 가능하도록 custom init을 제공한다.
    // CodingKeys는 synthesize되므로 명시하지 않는다.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.app = try c.decode(KSAppInfo.self, forKey: .app)
        self.build = try c.decode(KSBuildConfig.self, forKey: .build)
        self.windows = try c.decode([KSWindowConfig].self, forKey: .windows)
        self.security = try c.decodeIfPresent(KSSecurityConfig.self, forKey: .security) ?? .default
        self.tray = try c.decodeIfPresent(KSTrayConfig.self, forKey: .tray)
        self.menu = try c.decodeIfPresent(KSMenuConfig.self, forKey: .menu)
        self.notifications = try c.decodeIfPresent(KSNotificationConfig.self, forKey: .notifications)
        self.autostart = try c.decodeIfPresent(KSAutostartConfig.self, forKey: .autostart)
        self.deepLink = try c.decodeIfPresent(KSDeepLinkConfig.self, forKey: .deepLink)
        self.distribution =
            try c.decodeIfPresent(KSDistributionConfig.self, forKey: .distribution) ?? .default
        self.permissions =
            try c.decodeIfPresent(KSPermissionsConfig.self, forKey: .permissions) ?? .denied
        self.capabilities =
            try c.decodeIfPresent(KSCapabilitiesConfig.self, forKey: .capabilities)
    }
}
public struct KSAppInfo: Codable, Sendable, Equatable {
    /// 사용자에게 표시되는 애플리케이션 이름.
    public var name: String
    /// 앱 버전 문자열.
    public var version: String
    /// 역DNS 식별자 (macOS의 번들 ID, Windows의 AppUserModelID).
    public var identifier: String
    /// 선택적 앱 설명.
    public var description: String?
    /// 선택적 작성자 목록.
    public var authors: [String]?

    public init(
        name: String,
        version: String,
        identifier: String,
        description: String? = nil,
        authors: [String]? = nil
    ) {
        self.name = name
        self.version = version
        self.identifier = identifier
        self.description = description
        self.authors = authors
    }
}
public struct KSBuildConfig: Codable, Sendable, Equatable {
    /// 빌드된 프론트엔드 번들의 상대 경로 (프로젝트 루트 기준).
    /// 릴리스 빌드에서 Swift 리소스로 포함된다.
    public var frontendDist: String
    /// `Kalsae dev` 중 WebView가 로드하는 URL (예: Vite dev 서버).
    public var devServerURL: String
    /// CLI가 dev 서버를 시작하기 위해 실행하는 명령어.
    public var devCommand: String?
    /// CLI가 `frontendDist`를 생성하기 위해 실행하는 명령어.
    public var buildCommand: String?
    /// 패키징 시 소스맵(.map) 파일을 자동 제거한다.
    /// 프로덕션 번들 크기를 줄이고 소스 코드 노출을 방지한다.
    /// 기본값은 `true` — thin frontend 원칙에 따라 프로덕션에서 소스맵은 불필요하다.
    public var stripSourceMaps: Bool
    /// 패키징 시 추가로 제거할 파일 확장자 목록 (예: `["md", "br"]`).
    /// 소문자로 지정하며, 선행 `.`은 붙이지 않는다.
    public var stripExtensions: [String]
    /// `kalsae build` 시 번들 분석 리포트를 출력한다.
    /// 기본값은 `true` — 개발자가 번들 구성을 인지하도록 돕는다.
    public var bundleReport: Bool

    public init(
        frontendDist: String = "dist",
        devServerURL: String = "http://localhost:5173",
        devCommand: String? = nil,
        buildCommand: String? = nil,
        stripSourceMaps: Bool = true,
        stripExtensions: [String] = [],
        bundleReport: Bool = true
    ) {
        self.frontendDist = frontendDist
        self.devServerURL = devServerURL
        self.devCommand = devCommand
        self.buildCommand = buildCommand
        self.stripSourceMaps = stripSourceMaps
        self.stripExtensions = stripExtensions
        self.bundleReport = bundleReport
    }

    // 기본값이 있는 필드들을 JSON에서 생략 가능하도록 custom init을 제공한다.
    // CodingKeys는 synthesize되므로 명시하지 않는다.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.frontendDist = try c.decode(String.self, forKey: .frontendDist)
        self.devServerURL = try c.decode(String.self, forKey: .devServerURL)
        self.devCommand = try c.decodeIfPresent(String.self, forKey: .devCommand)
        self.buildCommand = try c.decodeIfPresent(String.self, forKey: .buildCommand)
        self.stripSourceMaps = try c.decodeIfPresent(Bool.self, forKey: .stripSourceMaps) ?? true
        self.stripExtensions = try c.decodeIfPresent([String].self, forKey: .stripExtensions) ?? []
        self.bundleReport = try c.decodeIfPresent(Bool.self, forKey: .bundleReport) ?? true
    }
}
