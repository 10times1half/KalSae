import Foundation

/// Describes a single window, either declared up front in `Kalsae.json`
/// or created dynamically at runtime via the Window API.
public struct KSWindowConfig: Codable, Sendable, Equatable, Identifiable {
    /// Stable identifier. Tauri-style. Used by the multi-window API and by
    /// cross-window event routing.
    public var label: String
    /// Title shown in the window chrome (and in the OS taskbar/Dock).
    public var title: String
    /// Initial width in logical (DPI-independent) points. Default `1024`.
    public var width: Int
    /// Initial height in logical (DPI-independent) points. Default `768`.
    public var height: Int

    /// Optional minimum content width. When `nil`, no lower bound is enforced.
    public var minWidth: Int?
    /// Optional minimum content height. When `nil`, no lower bound is enforced.
    public var minHeight: Int?
    /// Optional maximum content width. When `nil`, no upper bound is enforced.
    public var maxWidth: Int?
    /// Optional maximum content height. When `nil`, no upper bound is enforced.
    public var maxHeight: Int?

    /// Whether the user can resize the window by dragging its edges.
    public var resizable: Bool
    /// Whether the native window chrome (title bar, borders) is shown.
    /// `false` produces a borderless window suitable for custom title bars.
    public var decorations: Bool
    /// Whether the window background is transparent. Requires the page to
    /// also avoid painting an opaque background.
    public var transparent: Bool
    /// Whether the window starts in fullscreen mode.
    public var fullscreen: Bool
    /// Whether the window is visible immediately after creation. Set to
    /// `false` to perform deferred reveal once the page is ready.
    public var visible: Bool
    /// Whether the window is centered on the active screen at creation.
    public var center: Bool
    /// Whether the window stays above other top-level windows.
    public var alwaysOnTop: Bool

    /// Optional override for the URL loaded into this window. When `nil`, the
    /// app's default frontend entry point (`ks://localhost/` in release,
    /// `build.devServerURL` in dev) is used.
    public var url: String?

    /// `Identifiable` conformance — same as `label`.
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
        url: String? = nil
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
    }

    // 멤버와이즈 이니셔라이저의 기본값이 있는 필드를 `Kalsae.json`에서
    // 선택적으로 둘 수 있도록 커스텀 디코딩을 제공한다.
    private enum CodingKeys: String, CodingKey {
        case label, title, width, height
        case minWidth, minHeight, maxWidth, maxHeight
        case resizable, decorations, transparent, fullscreen
        case visible, center, alwaysOnTop, url
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
    }
}
