/// 앱의 최종 배포 대상을 나타낸다.
///
/// `kalsae build --store <value>` 와 `Kalsae.json` 의 `distribution.target`
/// 양쪽에서 동일하게 사용된다. 런타임에는 `KSApp.distributionTarget`로
/// 노출되어, PAL 백엔드가 스토어 정책에 맞춰 일부 기능을 no-op으로
/// 분기할 때 참조한다.
///
/// 정책 매핑(RFC-008):
///
/// | case              | 산출물                             | PAL 영향 |
/// | ----------------- | ---------------------------------- | -------- |
/// | `developer`       | 기존 NSIS / `.app` / `.AppImage`   | 없음 |
/// | `developerID`     | `.app` 서명 + notarize + staple    | 없음 (Hardened Runtime만) |
/// | `macAppStore`     | `.pkg` (productbuild)              | macOS 4~5개 백엔드가 no-op 분기 |
/// | `microsoftStore`  | `.msix` (signtool)                 | Windows 2개 백엔드가 no-op 분기 |
/// | `iosAppStore`     | `.ipa` (xcodebuild + altool)       | iOS stub 백엔드 채움 |
import Foundation

public enum KSDistributionTarget: String, Codable, Sendable, CaseIterable {
    /// 개발/내부 배포. 서명·공증·매니페스트 모두 사용자 선택. 기본값.
    case developer

    /// macOS Developer ID 서명 + notarize + staple (Gatekeeper 통과용).
    /// PAL 변경 없음. Hardened Runtime entitlements 기본 적용.
    case developerID = "developer-id"

    /// Mac App Store 배포. App Sandbox 강제, productbuild 로 `.pkg` 생성.
    /// 일부 PAL API (Deep-link register, 임의 경로 fs 접근 등)가 no-op 으로 분기된다.
    case macAppStore = "mac-app-store"

    /// Microsoft Store 배포. MSIX 패키지, AppxManifest 자동 생성.
    /// Autostart/Deep-link Registry 직접 쓰기가 매니페스트 선언으로 대체된다.
    case microsoftStore = "microsoft-store"

    /// iOS App Store 배포. xcodebuild archive + altool upload.
    case iosAppStore = "ios-app-store"

    /// CLI 단축 식별자 (예: `kalsae build --store mas`).
    public var shortName: String {
        switch self {
        case .developer: return "dev"
        case .developerID: return "devid"
        case .macAppStore: return "mas"
        case .microsoftStore: return "win-store"
        case .iosAppStore: return "ios-appstore"
        }
    }

    /// 짧은 식별자 또는 정식 rawValue 모두 받아 파싱한다.
    /// 알 수 없는 값은 `nil` 을 반환한다.
    public static func parse(_ raw: String) -> KSDistributionTarget? {
        let normalised = raw.lowercased()
        if let direct = KSDistributionTarget(rawValue: normalised) {
            return direct
        }
        for c in allCases where c.shortName == normalised {
            return c
        }
        return nil
    }

    /// App Sandbox 가 강제되는 스토어 대상인가?
    /// MAS / iOS App Store 가 해당된다.
    public var requiresAppSandbox: Bool {
        switch self {
        case .macAppStore, .iosAppStore: return true
        case .developer, .developerID, .microsoftStore: return false
        }
    }

    /// 매니페스트(AppxManifest, Info.plist `CFBundleURLTypes`) 기반 등록을
    /// 우선하고 PAL 런타임 등록을 비활성화해야 하는 스토어 대상인가?
    public var prefersManifestRegistration: Bool {
        switch self {
        case .macAppStore, .microsoftStore, .iosAppStore: return true
        case .developer, .developerID: return false
        }
    }
}
