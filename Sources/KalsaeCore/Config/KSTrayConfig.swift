import Foundation

/// System tray (status item) configuration.
public struct KSTrayConfig: Codable, Sendable, Equatable {
    /// Path, relative to project root, of the icon file. Platform layers
    /// pick an appropriate format (`.icns`/`.ico`/`.png`).
    public var icon: String
    public var tooltip: String?
    public var menu: [KSMenuItem]?
    /// Command id invoked on primary (left) click. When `nil`, the tray
    /// only shows the menu.
    public var onLeftClick: String?

    public init(icon: String,
                tooltip: String? = nil,
                menu: [KSMenuItem]? = nil,
                onLeftClick: String? = nil) {
        self.icon = icon
        self.tooltip = tooltip
        self.menu = menu
        self.onLeftClick = onLeftClick
    }
}
