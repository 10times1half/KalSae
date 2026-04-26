import Foundation

/// Security posture declared in `Kalsae.json`.
///
/// Kalsae enforces these at runtime — the command allowlist in particular
/// is the ONLY way JS code can reach Swift. There is no implicit opt-out.
public struct KSSecurityConfig: Codable, Sendable, Equatable {
    /// Content Security Policy injected into the default HTTP response
    /// headers served by the `ks://` scheme handler.
    public var csp: String

    /// Allowlist of `@KSCommand` identifiers callable from JS.
    ///
    /// When empty, no commands are reachable. When `nil`, the default
    /// (registered & not marked `internal`) set is used.
    public var commandAllowlist: [String]?

    /// Filesystem access policy for built-in `fs.*` commands.
    public var fs: KSFSScope

    /// Enable DevTools. Forced to `false` in release builds regardless of
    /// this setting.
    public var devtools: Bool

    /// Webview context-menu policy.
    /// - `.default`: native context menu (browser-style: Cut/Copy/Paste/Inspect).
    /// - `.disabled`: suppress the native menu entirely. The page may still
    ///   render its own custom menu in JS.
    public var contextMenu: ContextMenuPolicy

    /// Whether to allow the user to drag-drop external files into the
    /// webview. When `false` (default for Wails parity) the webview's
    /// built-in drop is disabled and the host receives drop events via
    /// the native drop target instead (`__ks.file.drop`).
    public var allowExternalDrop: Bool

    /// Shell-integration permission scope. Gates `__ks.shell.*` JS
    /// commands (`openExternal`, `showItemInFolder`, `moveToTrash`).
    public var shell: KSShellScope

    /// Notification permission scope. Gates `__ks.notification.*` JS
    /// commands (`requestPermission`, `post`, `cancel`).
    public var notifications: KSNotificationScope

    /// Policy values for `contextMenu`. See the `contextMenu` field doc.
    public enum ContextMenuPolicy: String, Codable, Sendable, Equatable {
        /// Native browser-style context menu (Cut/Copy/Paste/Inspect).
        case `default`
        /// Suppress the native context menu entirely.
        case disabled
    }

    public init(
        csp: String = KSSecurityConfig.defaultCSP,
        commandAllowlist: [String]? = nil,
        fs: KSFSScope = .init(),
        devtools: Bool = false,
        contextMenu: ContextMenuPolicy = .default,
        allowExternalDrop: Bool = false,
        shell: KSShellScope = .init(),
        notifications: KSNotificationScope = .init()
    ) {
        self.csp = csp
        self.commandAllowlist = commandAllowlist
        self.fs = fs
        self.devtools = devtools
        self.contextMenu = contextMenu
        self.allowExternalDrop = allowExternalDrop
        self.shell = shell
        self.notifications = notifications
    }

    private enum CodingKeys: String, CodingKey {
        case csp, commandAllowlist, fs, devtools, contextMenu, allowExternalDrop, shell, notifications
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.csp = try c.decodeIfPresent(String.self, forKey: .csp) ?? Self.defaultCSP
        self.commandAllowlist = try c.decodeIfPresent([String].self, forKey: .commandAllowlist)
        self.fs = try c.decodeIfPresent(KSFSScope.self, forKey: .fs) ?? .init()
        self.devtools = try c.decodeIfPresent(Bool.self, forKey: .devtools) ?? false
        self.contextMenu = try c.decodeIfPresent(ContextMenuPolicy.self, forKey: .contextMenu) ?? .default
        self.allowExternalDrop = try c.decodeIfPresent(Bool.self, forKey: .allowExternalDrop) ?? false
        self.shell = try c.decodeIfPresent(KSShellScope.self, forKey: .shell) ?? .init()
        self.notifications = try c.decodeIfPresent(KSNotificationScope.self, forKey: .notifications) ?? .init()
    }

    public static let defaultCSP =
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ks://localhost"

    public static let `default` = KSSecurityConfig()
}

/// Tauri-style filesystem scope. Paths support `$APP`, `$HOME`, `$DOCS`,
/// `$TEMP` placeholders resolved by the platform layer.
public struct KSFSScope: Codable, Sendable, Equatable {
    /// Glob-style allow patterns.
    public var allow: [String]
    /// Glob-style deny patterns, applied after `allow`.
    public var deny: [String]

    public init(allow: [String] = [], deny: [String] = []) {
        self.allow = allow
        self.deny = deny
    }
}

/// Permission scope for the `__ks.shell.*` command family. Each operation
/// is gated independently so a JS frontend cannot, for example, escalate
/// from "read clipboard" to "delete arbitrary files".
///
/// Defaults match the Wails-style "safe by default" posture:
///   * `openExternalSchemes` allows only `http`, `https`, `mailto`.
///   * `showItemInFolder` allowed.
///   * `moveToTrash` allowed (recoverable via Recycle Bin / Trash).
public struct KSShellScope: Codable, Sendable, Equatable {
    /// Allowed URL schemes for `openExternal`. `nil` means "no scheme
    /// restriction" (any URL is permitted). An empty array means
    /// `openExternal` is disabled. Scheme comparison is case-insensitive.
    public var openExternalSchemes: [String]?

    /// Whether `showItemInFolder` is permitted at all.
    public var showItemInFolder: Bool

    /// Whether `moveToTrash` is permitted at all.
    public var moveToTrash: Bool

    public init(
        openExternalSchemes: [String]? = ["http", "https", "mailto"],
        showItemInFolder: Bool = true,
        moveToTrash: Bool = true
    ) {
        self.openExternalSchemes = openExternalSchemes
        self.showItemInFolder = showItemInFolder
        self.moveToTrash = moveToTrash
    }

    private enum CodingKeys: String, CodingKey {
        case openExternalSchemes, showItemInFolder, moveToTrash
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `openExternalSchemes`는 "키 부재"(기본 안전 목록 사용)와
        // "키 존재하지만 null"(임의 스키마 허용)을 구분한다.
        if c.contains(.openExternalSchemes) {
            self.openExternalSchemes = try c.decodeIfPresent(
                [String].self, forKey: .openExternalSchemes)
        } else {
            self.openExternalSchemes = ["http", "https", "mailto"]
        }
        self.showItemInFolder = try c.decodeIfPresent(
            Bool.self, forKey: .showItemInFolder) ?? true
        self.moveToTrash = try c.decodeIfPresent(
            Bool.self, forKey: .moveToTrash) ?? true
    }

    /// Returns `true` when `scheme` (case-insensitive) is permitted by
    /// `openExternalSchemes`.
    public func permitsScheme(_ scheme: String) -> Bool {
        guard let openExternalSchemes else { return true }
        let lower = scheme.lowercased()
        return openExternalSchemes.contains { $0.lowercased() == lower }
    }
}

/// Permission scope for the `__ks.notification.*` command family. Each
/// operation is gated independently so a JS frontend cannot, for example,
/// silently spam toasts after the user has opted out.
///
/// Defaults match a "safe by default" posture:
///   * `post` allowed.
///   * `cancel` allowed.
///   * `requestPermission` allowed (the call is a no-op on Windows but
///     real on macOS).
public struct KSNotificationScope: Codable, Sendable, Equatable {
    /// Whether `__ks.notification.post` is permitted.
    public var post: Bool

    /// Whether `__ks.notification.cancel` is permitted.
    public var cancel: Bool

    /// Whether `__ks.notification.requestPermission` is permitted.
    public var requestPermission: Bool

    public init(
        post: Bool = true,
        cancel: Bool = true,
        requestPermission: Bool = true
    ) {
        self.post = post
        self.cancel = cancel
        self.requestPermission = requestPermission
    }

    private enum CodingKeys: String, CodingKey {
        case post, cancel, requestPermission
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.post = try c.decodeIfPresent(Bool.self, forKey: .post) ?? true
        self.cancel = try c.decodeIfPresent(Bool.self, forKey: .cancel) ?? true
        self.requestPermission = try c.decodeIfPresent(
            Bool.self, forKey: .requestPermission) ?? true
    }
}
