import Foundation

/// `Kalsae.json`의 루트 스키마.
///
/// 참조 문서는 `Examples/Kalsae.sample.json`을 참고하라.
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

    public init(
        app: KSAppInfo,
        build: KSBuildConfig,
        windows: [KSWindowConfig],
        security: KSSecurityConfig = .default,
        tray: KSTrayConfig? = nil,
        menu: KSMenuConfig? = nil,
        notifications: KSNotificationConfig? = nil,
        autostart: KSAutostartConfig? = nil,
        deepLink: KSDeepLinkConfig? = nil
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
    }

    // `security` 등 필수가 아닌 섹션은 JSON에서 생략 가능하도록 한다.
    private enum CodingKeys: String, CodingKey {
        case app, build, windows, security, tray, menu, notifications
        case autostart, deepLink
    }

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
    }
}

// MARK: - 앱 메타데이터

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

    public init(name: String,
                version: String,
                identifier: String,
                description: String? = nil,
                authors: [String]? = nil) {
        self.name = name
        self.version = version
        self.identifier = identifier
        self.description = description
        self.authors = authors
    }
}

// MARK: - 빌드 / 개발 서버

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

    public init(frontendDist: String = "dist",
                devServerURL: String = "http://localhost:5173",
                devCommand: String? = nil,
                buildCommand: String? = nil) {
        self.frontendDist = frontendDist
        self.devServerURL = devServerURL
        self.devCommand = devCommand
        self.buildCommand = buildCommand
    }
}
