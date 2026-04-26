import Foundation

/// Root schema for `Kalsae.json`.
///
/// See `Examples/Kalsae.sample.json` for a reference document.
public struct KSConfig: Codable, Sendable, Equatable {
    public var app: KSAppInfo
    public var build: KSBuildConfig
    public var windows: [KSWindowConfig]
    public var security: KSSecurityConfig
    public var tray: KSTrayConfig?
    public var menu: KSMenuConfig?
    public var notifications: KSNotificationConfig?

    public init(
        app: KSAppInfo,
        build: KSBuildConfig,
        windows: [KSWindowConfig],
        security: KSSecurityConfig = .default,
        tray: KSTrayConfig? = nil,
        menu: KSMenuConfig? = nil,
        notifications: KSNotificationConfig? = nil
    ) {
        self.app = app
        self.build = build
        self.windows = windows
        self.security = security
        self.tray = tray
        self.menu = menu
        self.notifications = notifications
    }

    // `security` 등 필수가 아닌 섹션은 JSON에서 생략 가능하도록 한다.
    private enum CodingKeys: String, CodingKey {
        case app, build, windows, security, tray, menu, notifications
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
    }
}

// MARK: - App metadata

public struct KSAppInfo: Codable, Sendable, Equatable {
    public var name: String
    public var version: String
    /// Reverse-DNS identifier (bundle id on macOS, AppUserModelID on Windows).
    public var identifier: String
    public var description: String?
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

// MARK: - Build / dev server

public struct KSBuildConfig: Codable, Sendable, Equatable {
    /// Relative path (from project root) of the built frontend bundle.
    /// Embedded as Swift resources in release builds.
    public var frontendDist: String
    /// URL that WebView loads during `Kalsae dev` (e.g. Vite dev server).
    public var devServerURL: String
    /// Command executed by the CLI to start the dev server.
    public var devCommand: String?
    /// Command executed by the CLI to produce `frontendDist`.
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
