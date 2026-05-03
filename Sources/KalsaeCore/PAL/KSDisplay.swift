public import Foundation

// MARK: - KSRect

/// 정수 픽셀 좌표계의 직사각형 영역 (가상 데스크톱 기준).
///
/// DPI-독립 논리 픽셀 단위이다. 플랫폼은 각 `scaleFactor`에 맞춰
/// 물리 픽셀 ↔ 논리 픽셀 변환을 처리한다.
public struct KSRect: Codable, Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// `other`가 `self` 경계 안에 완전히 포함되는지 확인한다.
    public func contains(_ other: KSRect) -> Bool {
        other.x >= x
            && other.y >= y
            && other.x + other.width <= x + width
            && other.y + other.height <= y + height
    }
}

// MARK: - KSDisplayInfo

/// 단일 물리/가상 디스플레이에 대한 런타임 정보.
///
/// `KSWindowBackend.listDisplays()` / `currentDisplay(_:)` 로 얻는다.
public struct KSDisplayInfo: Codable, Sendable, Equatable {
    /// 플랫폼-스코프 안정 식별자.
    /// - Windows: `HMONITOR` 포인터 값의 hex 문자열 (예: `"000000000001005C"`)
    /// - macOS: `CGDirectDisplayID` (UInt32 decimal string)
    /// - Linux: DRM connector name (예: `"DP-1"`)
    public var id: String

    /// 사람이 읽는 디스플레이 이름.
    /// - Windows: `DISPLAY_DEVICE.DeviceName` (예: `"\\\\.\\\DISPLAY1"`)
    public var name: String

    /// 가상 데스크톱 좌표 기준의 전체 디스플레이 영역 (논리 픽셀).
    public var bounds: KSRect

    /// 작업 표시줄, 독 등을 제외한 유효 작업 영역 (논리 픽셀).
    public var workArea: KSRect

    /// DPI 스케일 팩터 (예: 1.0 = 96 DPI, 1.5 = 144 DPI, 2.0 = 192 DPI).
    public var scaleFactor: Double

    /// 화면 주사율 (Hz). 알 수 없는 경우 `nil`.
    public var refreshRate: Int?

    /// 시스템 주 디스플레이 여부.
    public var isPrimary: Bool

    public init(
        id: String,
        name: String,
        bounds: KSRect,
        workArea: KSRect,
        scaleFactor: Double,
        refreshRate: Int?,
        isPrimary: Bool
    ) {
        self.id = id
        self.name = name
        self.bounds = bounds
        self.workArea = workArea
        self.scaleFactor = scaleFactor
        self.refreshRate = refreshRate
        self.isPrimary = isPrimary
    }
}

// MARK: - KSTaskbarProgress

/// 작업 표시줄 버튼에 표시할 진행 상태.
///
/// `KSWindowBackend.setTaskbarProgress(_:progress:)` 에 전달한다.
public enum KSTaskbarProgress: Codable, Sendable, Equatable {
    /// 진행 표시를 숨긴다 (기본 상태).
    case none
    /// 불확정 진행 애니메이션 (로딩 스피너 등).
    case indeterminate
    /// 정상 진행 (0.0 – 1.0).
    case normal(Double)
    /// 오류 상태 진행 (빨간색, 0.0 – 1.0).
    case error(Double)
    /// 일시 중지 진행 (노란색, 0.0 – 1.0).
    case paused(Double)

    // MARK: Codable (manual — enum with associated values)
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Tag: String, Codable { case none, indeterminate, normal, error, paused }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .type)
        switch tag {
        case .none: self = .none
        case .indeterminate: self = .indeterminate
        case .normal: self = .normal(try c.decodeIfPresent(Double.self, forKey: .value) ?? 0)
        case .error: self = .error(try c.decodeIfPresent(Double.self, forKey: .value) ?? 0)
        case .paused: self = .paused(try c.decodeIfPresent(Double.self, forKey: .value) ?? 0)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode(Tag.none, forKey: .type)
        case .indeterminate:
            try c.encode(Tag.indeterminate, forKey: .type)
        case .normal(let v):
            try c.encode(Tag.normal, forKey: .type)
            try c.encode(v, forKey: .value)
        case .error(let v):
            try c.encode(Tag.error, forKey: .type)
            try c.encode(v, forKey: .value)
        case .paused(let v):
            try c.encode(Tag.paused, forKey: .type)
            try c.encode(v, forKey: .value)
        }
    }
}
