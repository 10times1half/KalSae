import Foundation

/// 시스템 트레이(상태 항목) 설정.
public struct KSTrayConfig: Codable, Sendable, Equatable {
    /// 아이콘 파일 경로. 프로젝트 루트 기준 상대 경로이며,
    /// 플랫폼 레이어가 적절한 형식(`.icns`/`.ico`/`.png`)을 고른다.
    public var icon: String
    /// 트레이 항목 위에 마우스를 올렸을 때 보이는 툴팁.
    public var tooltip: String?
    /// 트레이 아이콘 클릭 또는 우클릭 시 표시할 메뉴.
    public var menu: [KSMenuItem]?
    /// 기본(왼쪽) 클릭 시 실행할 명령 ID.
    /// `nil`이면 트레이는 메뉴만 표시한다.
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
