/// 앱의 최종 배포 대상을 나타낸다.
///
/// `kalsae build --store <value>` 와 `kalsae.json` 의 `distribution.target`
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
///
/// ---
///
/// ### 향후 구현자 메모 — Updater Android/iOS 가드 (RFC-001 / RFC-007 §3.5)
///
/// 본 enum 자체는 자체 업데이트(self-update)와 직접 관련이 없으나, 향후
/// `Sources/KalsaePluginUpdater/` 모듈이 도입될 때 **반드시** 다음 정책을
/// 코드로 강제해야 한다(현재는 RFC 문서로만 기록되어 있다):
///
/// - `makeInstaller(for:)` 는 `os(Android)` / `os(iOS)` 에서 즉시
///   `KSError(code: .unsupportedPlatform, ...)` 을 throw 한다. 모바일 앱
///   업데이트는 Play Store / App Store 메커니즘에 위임한다.
/// - IPC 표(RFC-007 §3.5.2): `kalsae.updater.check` 만 허용,
///   `kalsae.updater.download` / `kalsae.updater.install` 은 거부,
///   `kalsae.updater.cancel` 은 no-op.
/// - 매니페스트의 `playstore` / `appstore` installerType 값은 자체 설치가
///   아니라 "스토어로 이동" 안내용 메타데이터로만 기능한다.
///
/// 누락 시 정책 위반(스토어 거절 사유) 및 보안 회귀로 이어지므로,
/// `KalsaePluginUpdater` 의 PR 에서 위 가드 + Android 테스트를 반드시
/// 함께 추가할 것. 본 메모는 [Docs/RFCs/RFC-001-updater.md](../../../Docs/RFCs/RFC-001-updater.md)
/// §비목표 와 [Docs/RFCs/RFC-007-android-release.md](../../../Docs/RFCs/RFC-007-android-release.md)
/// §3.5 의 단일 발견지점(single point of discovery)으로 기능한다.
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
