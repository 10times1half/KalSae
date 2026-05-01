import Foundation

/// `Kalsae.json`에 선언되는 보안 정책.
///
/// Kalsae는 이를 런타임에 강제한다. 특히 명령 허용 목록은
/// JS 코드가 Swift에 도달할 수 있는 유일한 경로이며,
/// 암묵적인 opt-out은 없다.
public struct KSSecurityConfig: Codable, Sendable, Equatable {
    /// `ks://` 스킴 핸들러가 제공하는 기본 HTTP 응답 헤더에 주입되는
    /// Content Security Policy.
    public var csp: String

    /// JS에서 호출 가능한 `@KSCommand` 식별자의 허용 목록.
    ///
    /// 비어 있으면 어떤 명령도 도달할 수 없고,
    /// `nil`이면 기본 집합(등록되었고 `internal`로 표시되지 않은 명령)을 사용한다.
    public var commandAllowlist: [String]?

    /// 내장 `fs.*` 명령에 대한 파일시스템 접근 정책.
    public var fs: KSFSScope

    /// DevTools 활성화 여부.
    /// 릴리스 빌드에서는 이 설정과 무관하게 강제로 `false`가 된다.
    public var devtools: Bool

    /// WebView 컨텍스트 메뉴 정책.
    /// - `.default`: 네이티브 컨텍스트 메뉴(브라우저 스타일: 잘라내기/복사/붙여넣기/검사).
    /// - `.disabled`: 네이티브 메뉴를 완전히 숨긴다. 페이지는 여전히 JS로
    ///   자체 커스텀 메뉴를 렌더링할 수 있다.
    public var contextMenu: ContextMenuPolicy

    /// 사용자가 외부 파일을 WebView에 드래그 앤 드롭할 수 있게 할지 여부.
    /// `false`이면(Wails와 동일한 기본값) WebView의 내장 drop이 비활성화되고,
    /// 호스트가 대신 네이티브 drop target을 통해 drop 이벤트(`__ks.file.drop`)를 받는다.
    public var allowExternalDrop: Bool

    /// 셸 통합 권한 범위.
    /// `__ks.shell.*` JS 명령(`openExternal`, `showItemInFolder`, `moveToTrash`)을 제어한다.
    public var shell: KSShellScope

    /// 알림 권한 범위.
    /// `__ks.notification.*` JS 명령(`requestPermission`, `post`, `cancel`)을 제어한다.
    public var notifications: KSNotificationScope

    /// HTTP fetch 권한 범위.
    /// `__ks.http.fetch`를 제어하며, 기본값은 비어 있으므로 호스트 앱이
    /// 신뢰할 오리진을 선언하기 전까지 JS 측은 네트워크에 접근할 수 없다.
    public var http: KSHTTPScope

    /// JS에서 초당 허용되는 IPC 명령 호출의 최대 수.
    /// burst는 이 속도를 잠시 넘는 짧은 급증을 허용한다.
    /// `nil`이면 속도 제한을 비활성화한다(하위 호환용 기본값).
    ///
    /// 권장 운영값은 `rate: 100, burst: 200`이다.
    public var commandRateLimit: KSCommandRateLimit?

    /// WebView 다운로드 정책.
    /// 기본값은 비활성화이며, 활성화하면 페이지가 다운로드를 시작할 수 있고
    /// 호스트 프로세스는 `__ks.webview.downloadStarting` 이벤트로 이를 관찰할 수 있다.
    public var downloads: KSDownloadScope

    /// WebView2의 `add_NavigationStarting` 핸들러로 강제되는
    /// 최상위 네비게이션 허용 목록.
    /// `allow` 목록이 비어 있으면 "제한 없음"(기존 동작)을 뜻한다.
    /// 비어 있지 않으면 목록 밖 URL로의 이동은 취소되고,
    /// 선택적으로 사용자의 기본 브라우저에서 열 수 있다.
    public var navigation: KSNavigationScope

    /// `contextMenu` 필드에 대한 정책 값.
    public enum ContextMenuPolicy: String, Codable, Sendable, Equatable {
        /// 네이티브 브라우저 스타일 컨텍스트 메뉴(잘라내기/복사/붙여넣기/검사).
        case `default`
        /// 네이티브 컨텍스트 메뉴를 완전히 숨긴다.
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
        notifications: KSNotificationScope = .init(),
        http: KSHTTPScope = .init(),
        downloads: KSDownloadScope = .init(),
        navigation: KSNavigationScope = .init(),
        commandRateLimit: KSCommandRateLimit? = nil
    ) {
        self.csp = csp
        self.commandAllowlist = commandAllowlist
        self.fs = fs
        self.devtools = devtools
        self.contextMenu = contextMenu
        self.allowExternalDrop = allowExternalDrop
        self.shell = shell
        self.notifications = notifications
        self.http = http
        self.downloads = downloads
        self.navigation = navigation
        self.commandRateLimit = commandRateLimit
    }

    private enum CodingKeys: String, CodingKey {
        case csp, commandAllowlist, fs, devtools, contextMenu, allowExternalDrop
        case shell, notifications, http, downloads, navigation, commandRateLimit
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
        self.http = try c.decodeIfPresent(KSHTTPScope.self, forKey: .http) ?? .init()
        self.downloads = try c.decodeIfPresent(KSDownloadScope.self, forKey: .downloads) ?? .init()
        self.navigation = try c.decodeIfPresent(KSNavigationScope.self, forKey: .navigation) ?? .init()
        self.commandRateLimit = try c.decodeIfPresent(KSCommandRateLimit.self, forKey: .commandRateLimit)
    }

    public static let defaultCSP =
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ks://localhost"

    public static let `default` = KSSecurityConfig()
}

/// Tauri 스타일 파일시스템 범위.
/// 경로는 플랫폼 레이어가 해석하는 `$APP`, `$HOME`, `$DOCS`, `$TEMP`
/// 플레이스홀더를 지원한다.
public struct KSFSScope: Codable, Sendable, Equatable {
    /// 글롭 스타일 허용 패턴.
    public var allow: [String]
    /// 글롭 스타일 거부 패턴. `allow` 이후에 적용된다.
    public var deny: [String]

    public init(allow: [String] = [], deny: [String] = []) {
        self.allow = allow
        self.deny = deny
    }
}

/// `__ks.shell.*` 명령군에 대한 권한 범위.
/// 각 동작은 독립적으로 제어되어, 예를 들어 JS 프론트엔드가
/// "클립보드 읽기"에서 "임의 파일 삭제"로 권한을 확장하지 못하게 한다.
///
/// 기본값은 Wails 스타일의 "기본적으로 안전" 정책을 따른다.
/// `openExternalSchemes`는 `http`, `https`, `mailto`만 허용하고,
/// `showItemInFolder`와 `moveToTrash`는 허용된다.
public struct KSShellScope: Codable, Sendable, Equatable {
    /// `openExternal`에 허용되는 URL 스킴.
    /// `nil`은 "스킴 제한 없음"(모든 URL 허용)을 뜻하고,
    /// 빈 배열은 `openExternal` 비활성화를 뜻한다.
    /// 스킴 비교는 대소문자를 구분하지 않는다.
    public var openExternalSchemes: [String]?

    /// `showItemInFolder` 자체를 허용할지 여부.
    public var showItemInFolder: Bool

    /// `moveToTrash` 자체를 허용할지 여부.
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

    /// `scheme`이(대소문자 무시) `openExternalSchemes`에 의해 허용되면 `true`를 반환한다.
    public func permitsScheme(_ scheme: String) -> Bool {
        guard let openExternalSchemes else { return true }
        let lower = scheme.lowercased()
        return openExternalSchemes.contains { $0.lowercased() == lower }
    }
}

/// `__ks.notification.*` 명령군에 대한 권한 범위.
/// 각 동작은 독립적으로 제어되어, 예를 들어 사용자가 거부한 뒤에도
/// JS 프론트엔드가 조용히 토스트를 남발하지 못하게 한다.
///
/// 기본값은 "기본적으로 안전" 정책을 따른다.
/// `post`, `cancel`, `requestPermission`이 모두 허용된다.
public struct KSNotificationScope: Codable, Sendable, Equatable {
    /// `__ks.notification.post` 허용 여부.
    public var post: Bool

    /// `__ks.notification.cancel` 허용 여부.
    public var cancel: Bool

    /// `__ks.notification.requestPermission` 허용 여부.
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
