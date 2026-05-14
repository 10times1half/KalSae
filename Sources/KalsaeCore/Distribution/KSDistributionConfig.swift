/// 스토어 배포 빌드용 메타데이터(`Kalsae.json` 의 `distribution` 섹션).
///
/// 본 섹션이 생략되면 `KSDistributionConfig.default` 가 사용되며,
/// 그 경우 빌드는 일반 개발 산출물(`KSDistributionTarget.developer`)로
/// 수행된다.
///
/// CLI 의 `--store` 플래그가 본 섹션의 `target` 값을 덮어쓴다. 즉
/// `Kalsae.json` 은 권장 기본값을, `--store` 는 1회성 오버라이드를
/// 담당한다. 양쪽 모두 미지정이면 `developer`.
import Foundation

public struct KSDistributionConfig: Codable, Sendable, Equatable {
    /// 권장 배포 대상. CLI `--store` 가 우선한다.
    public var target: KSDistributionTarget

    /// Apple Developer Team ID (10자리, 예: `ABCDE12345`).
    /// `mas` / `developer-id` / `ios-app-store` 빌드에서 entitlements 와
    /// 서명 식별자 매핑에 사용된다. 일반 `developer` 빌드에서는 무시된다.
    public var appleTeamID: String?

    /// MSIX `<Identity Publisher>` 에 사용되는 X.500 DN.
    /// 예: `CN=Acme Corp, O=Acme Corp, C=KR`. Microsoft Partner Center 에
    /// 등록된 Publisher CN 과 정확히 일치해야 한다.
    public var windowsPublisher: String?

    /// 번들/패키지 식별자 오버라이드. 비워두면 `app.identifier` 를 사용한다.
    /// 스토어마다 사용되는 형식이 다르므로 (Apple: 역DNS, MSIX: GUID 또는
    /// 역DNS) 필요 시 명시적으로 지정한다.
    public var bundleIdentifier: String?

    public init(
        target: KSDistributionTarget = .developer,
        appleTeamID: String? = nil,
        windowsPublisher: String? = nil,
        bundleIdentifier: String? = nil
    ) {
        self.target = target
        self.appleTeamID = appleTeamID
        self.windowsPublisher = windowsPublisher
        self.bundleIdentifier = bundleIdentifier
    }

    /// 일반 개발 배포 (서명/공증/매니페스트 없음).
    public static let `default` = KSDistributionConfig()

    private enum CodingKeys: String, CodingKey {
        case target, appleTeamID, windowsPublisher, bundleIdentifier
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let rawTarget = try c.decodeIfPresent(String.self, forKey: .target) {
            guard let parsed = KSDistributionTarget.parse(rawTarget) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .target, in: c,
                    debugDescription:
                        "Unknown distribution.target '\(rawTarget)'. Allowed: developer, developer-id, mac-app-store, microsoft-store, ios-app-store (or short: dev, devid, mas, win-store, ios-appstore)."
                )
            }
            self.target = parsed
        } else {
            self.target = .developer
        }
        self.appleTeamID = try c.decodeIfPresent(String.self, forKey: .appleTeamID)
        self.windowsPublisher = try c.decodeIfPresent(String.self, forKey: .windowsPublisher)
        self.bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
    }
}
