/// 새 창에 요청되는 초기 표시 상태.
import Foundation

/// 일반 RGBA 색상(채널당 0-255).
/// `__ks.window.setBackgroundColor`가 사용하는 JS 표면을 그대로 따른다.

/// 창 배경에 요청되는 시스템 백드롭 종류.
/// Windows 11(build 22621 이상)에서는 `DWMWA_SYSTEMBACKDROP_TYPE`에 매핑된다.
/// 알 수 없는 값은 조용히 `auto`로 폴백한다.

/// WebView 수준의 시각/런타임 재정의.
/// 모든 필드를 선택적으로 두어, 이전 릴리스용 `Kalsae.json`도 계속 로드되게 한다.

/// `Kalsae.json`에 미리 선언되거나 Window API로 런타임에 동적으로 생성되는
/// 단일 창을 설명한다.
public enum KSWindowStartState: String, Codable, Sendable, CaseIterable {
    case normal
    case maximized
    case minimized
    case fullscreen
}
public struct KSColorRGBA: Codable, Sendable, Equatable {
    public var r: Int
    public var g: Int
    public var b: Int
    public var a: Int
    public init(r: Int, g: Int, b: Int, a: Int = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}
public enum KSWindowBackdrop: String, Codable, Sendable, CaseIterable {
    case auto  // DWMSBT_AUTO            (0)
    case none  // DWMSBT_NONE            (1)
    case mica  // DWMSBT_MAINWINDOW      (2)
    case acrylic  // DWMSBT_TRANSIENTWINDOW (3)
    case tabbed  // DWMSBT_TABBEDWINDOW    (4)
}
public struct KSWebViewOptions: Codable, Sendable, Equatable {
    /// `true`이면 WebView2 컨트롤러가 투명한 기본 배경
    /// (`ICoreWebView2Controller2.DefaultBackgroundColor`)으로 렌더링된다.
    /// 효과가 보이려면 호스팅 창도 투명 모드(`KSWindowConfig.transparent`)를 켜야 한다.
    public var transparent: Bool
    /// 선택적 Windows 11 시스템 백드롭 요청.
    /// `DwmSetWindowAttribute(DWMWA_SYSTEMBACKDROP_TYPE)`로 적용되며,
    /// 구버전 빌드에서는 무시된다.
    public var backdropType: KSWindowBackdrop?
    /// 페이지에서 터치/트랙패드 핀치 줌을 비활성화한다.
    /// `ICoreWebView2Settings5.IsPinchZoomEnabled`를 감싼다.
    public var disablePinchZoom: Bool
    /// 컨트롤러에 적용할 초기 확대 배율(`put_ZoomFactor`).
    /// `1.0`은 원래 배율이며 `nil`이면 WebView 기본값을 유지한다.
    public var zoomFactor: Double?
    /// WebView2 사용자 데이터 폴더의 창별 재정의.
    /// 설정되면 `kalsae.runtime.json`보다 우선하며, 여러 창/앱 변형이
    /// 브라우저 프로필(쿠키, IndexedDB 등)을 분리해 유지하는 데 사용된다.
    /// 경로에는 부팅 시 확장되는 Windows `%VAR%` 환경 변수 토큰을 포함할 수 있다.
    public var userDataPath: String?

    public init(
        transparent: Bool = false,
        backdropType: KSWindowBackdrop? = nil,
        disablePinchZoom: Bool = false,
        zoomFactor: Double? = nil,
        userDataPath: String? = nil
    ) {
        self.transparent = transparent
        self.backdropType = backdropType
        self.disablePinchZoom = disablePinchZoom
        self.zoomFactor = zoomFactor
        self.userDataPath = userDataPath
    }

    private enum CodingKeys: String, CodingKey {
        case transparent, backdropType, disablePinchZoom, zoomFactor, userDataPath
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.transparent = try c.decodeIfPresent(Bool.self, forKey: .transparent) ?? false
        self.backdropType = try c.decodeIfPresent(KSWindowBackdrop.self, forKey: .backdropType)
        self.disablePinchZoom = try c.decodeIfPresent(Bool.self, forKey: .disablePinchZoom) ?? false
        self.zoomFactor = try c.decodeIfPresent(Double.self, forKey: .zoomFactor)
        self.userDataPath = try c.decodeIfPresent(String.self, forKey: .userDataPath)
    }
}
public struct KSWindowConfig: Codable, Sendable, Equatable, Identifiable {
    /// 안정적인 식별자. Tauri 스타일이며 멀티 윈도우 API와 창 간 이벤트 라우팅에 사용된다.
    public var label: String
    /// 창 크롬(및 OS 작업 표시줄/Dock)에 표시되는 제목.
    public var title: String
    /// 논리 좌표(DPI 독립 포인트) 기준 초기 너비. 기본값은 `1024`.
    public var width: Int
    /// 논리 좌표(DPI 독립 포인트) 기준 초기 높이. 기본값은 `768`.
    public var height: Int

    /// 선택적 최소 콘텐츠 너비. `nil`이면 하한을 강제하지 않는다.
    public var minWidth: Int?
    /// 선택적 최소 콘텐츠 높이. `nil`이면 하한을 강제하지 않는다.
    public var minHeight: Int?
    /// 선택적 최대 콘텐츠 너비. `nil`이면 상한을 강제하지 않는다.
    public var maxWidth: Int?
    /// 선택적 최대 콘텐츠 높이. `nil`이면 상한을 강제하지 않는다.
    public var maxHeight: Int?

    /// 사용자가 가장자리를 드래그해 창 크기를 조절할 수 있는지 여부.
    public var resizable: Bool
    /// 네이티브 창 크롬(제목 표시줄, 테두리)을 표시할지 여부.
    /// `false`이면 커스텀 타이틀바에 적합한 무테 창이 된다.
    public var decorations: Bool
    /// 창 배경을 투명하게 할지 여부. 페이지도 불투명 배경을 그리지 않아야 한다.
    ///
    /// **플랫폼 지원:**
    /// - **Windows**: 구현됨. `WS_EX_LAYERED` + WebView2 컨트롤러 알파 0
    ///   조합으로 DWM이 데스크탑을 합성한다. `backgroundColor`를 명시적으로
    ///   지정하면 알파 채널이 0이 아닌 한 합성 효과가 가려질 수 있다.
    ///   `KSWebViewOptions.backdropType` 이 `mica` / `acrylic` / `tabbed`
    ///   중 하나이고 본 값이 `false`이면 호스트가 자동으로 `true`로 승격하고
    ///   1회 경고 로그를 남긴다 (시각 효과를 표시하기 위한 필수 조건).
    /// - **macOS / Linux / iOS / Android**: 미구현 (v0.3 시점). `true`로
    ///   설정해도 무시되며 첫 호출 시 경고 로그를 1회 남긴다.
    public var transparent: Bool
    /// 창이 전체 화면 모드로 시작하는지 여부.
    public var fullscreen: Bool
    /// 창 생성 직후 바로 표시할지 여부.
    /// 페이지 준비 후 지연 표시하려면 `false`로 둔다.
    public var visible: Bool
    /// 생성 시 활성 화면 중앙에 배치할지 여부.
    public var center: Bool
    /// 다른 최상위 창들 위에 항상 머무를지 여부.
    public var alwaysOnTop: Bool

    /// 이 창에 로드할 URL의 선택적 재정의.
    /// `nil`이면 앱의 기본 프론트엔드 진입점(릴리스의 `ks://localhost/`,
    /// 개발 중의 `build.devServerURL`)을 사용한다.
    public var url: String?

    // MARK: - Phase C 라이프사이클 / 장식 옵션

    /// 초기 표시 상태. `nil`이면 호환성을 위해 기존 `fullscreen` 플래그로 폴백한다.
    public var startState: KSWindowStartState?

    /// 닫기 시 창을 파괴하지 않고 숨긴다(트레이 앱 패턴).
    /// close interceptor 위에서 구현된다.
    public var hideOnClose: Bool

    /// 선택적 초기 배경색.
    /// 설정되면 `__ks.window.setBackgroundColor`와 같은 경로로 창 생성 직후 적용된다.
    public var backgroundColor: KSColorRGBA?

    /// 제목 표시줄 좌상단에 표시되는 작은 아이콘을 숨긴다
    /// (Windows의 `WM_SETICON(ICON_SMALL, NULL)`).
    /// 창은 여전히 앱 아이콘과 함께 작업 표시줄에 나타난다.
    public var disableWindowIcon: Bool

    /// 이 창을 화면 캡처/스크린샷 대상에서 제외한다.
    /// (Windows 2004 이상에서 `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` 사용,
    /// 구버전 빌드에서는 조용히 무시된다.)
    public var contentProtection: Bool

    /// 선택적 WebView 수준 시각/런타임 재정의.
    /// WebView2 컨트롤러 생성 후 시작 시 적용된다.
    /// 필드별 설명은 `KSWebViewOptions`를 참고한다.
    public var webview: KSWebViewOptions?

    /// `true`이면 창의 마지막 위치/크기/최대화 상태를 실행 간에 보존하여
    /// 다음 부팅 때 복원한다.
    /// Windows에서는 `%APPDATA%\<identifier>\`, macOS에서는
    /// `~/Library/Application Support/<identifier>/` 아래 저장된다.
    /// 테스트의 부팅 경로를 결정적으로 유지하기 위해 기본값은 꺼져 있다.
    public var persistState: Bool

    /// `Identifiable` 준수용 식별자. `label`과 동일하다.
    public var id: String { label }

    public init(
        label: String,
        title: String,
        width: Int = 1024,
        height: Int = 768,
        minWidth: Int? = nil,
        minHeight: Int? = nil,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        resizable: Bool = true,
        decorations: Bool = true,
        transparent: Bool = false,
        fullscreen: Bool = false,
        visible: Bool = true,
        center: Bool = true,
        alwaysOnTop: Bool = false,
        url: String? = nil,
        startState: KSWindowStartState? = nil,
        hideOnClose: Bool = false,
        backgroundColor: KSColorRGBA? = nil,
        disableWindowIcon: Bool = false,
        contentProtection: Bool = false,
        webview: KSWebViewOptions? = nil,
        persistState: Bool = false
    ) {
        self.label = label
        self.title = title
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.resizable = resizable
        self.decorations = decorations
        self.transparent = transparent
        self.fullscreen = fullscreen
        self.visible = visible
        self.center = center
        self.alwaysOnTop = alwaysOnTop
        self.url = url
        self.startState = startState
        self.hideOnClose = hideOnClose
        self.backgroundColor = backgroundColor
        self.disableWindowIcon = disableWindowIcon
        self.contentProtection = contentProtection
        self.webview = webview
        self.persistState = persistState
    }

    // 멤버와이즈 이니셔라이저의 기본값이 있는 필드를 `Kalsae.json`에서
    // 선택적으로 둘 수 있도록 커스텀 디코딩을 제공한다.
    private enum CodingKeys: String, CodingKey {
        case label, title, width, height
        case minWidth, minHeight, maxWidth, maxHeight
        case resizable, decorations, transparent, fullscreen
        case visible, center, alwaysOnTop, url
        case startState, hideOnClose, backgroundColor
        case disableWindowIcon, contentProtection
        case webview
        case persistState
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try c.decode(String.self, forKey: .label)
        self.title = try c.decode(String.self, forKey: .title)
        self.width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 1024
        self.height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 768
        self.minWidth = try c.decodeIfPresent(Int.self, forKey: .minWidth)
        self.minHeight = try c.decodeIfPresent(Int.self, forKey: .minHeight)
        self.maxWidth = try c.decodeIfPresent(Int.self, forKey: .maxWidth)
        self.maxHeight = try c.decodeIfPresent(Int.self, forKey: .maxHeight)
        self.resizable = try c.decodeIfPresent(Bool.self, forKey: .resizable) ?? true
        self.decorations = try c.decodeIfPresent(Bool.self, forKey: .decorations) ?? true
        self.transparent = try c.decodeIfPresent(Bool.self, forKey: .transparent) ?? false
        self.fullscreen = try c.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? false
        self.visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        self.center = try c.decodeIfPresent(Bool.self, forKey: .center) ?? true
        self.alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
        self.startState = try c.decodeIfPresent(KSWindowStartState.self, forKey: .startState)
        self.hideOnClose = try c.decodeIfPresent(Bool.self, forKey: .hideOnClose) ?? false
        self.backgroundColor = try c.decodeIfPresent(KSColorRGBA.self, forKey: .backgroundColor)
        self.disableWindowIcon = try c.decodeIfPresent(Bool.self, forKey: .disableWindowIcon) ?? false
        self.contentProtection = try c.decodeIfPresent(Bool.self, forKey: .contentProtection) ?? false
        self.webview = try c.decodeIfPresent(KSWebViewOptions.self, forKey: .webview)
        self.persistState = try c.decodeIfPresent(Bool.self, forKey: .persistState) ?? false
    }
}
