/// 사용자에게 명시적 동의를 요구하는 OS 권한(Camera, Microphone 등).
///
/// `Kalsae.json` 의 `permissions` 섹션에 들어가며, 스토어 빌드 시
/// 다음 산출물을 자동 생성하는 단일 진실 공급원(source of truth)이다.
///
/// - macOS / iOS: `Info.plist` 의 `NS*UsageDescription` 키 + sandbox
///   entitlement (예: `com.apple.security.device.camera`).
/// - Windows MSIX: `AppxManifest.xml` 의 `<Capabilities>` (예: `webcam`).
///
/// 모든 필드는 기본 `false` (default-deny). 명시적으로 `true` 로 설정한
/// 권한만 매니페스트/Info.plist 에 반영된다. 사용 사유 문자열을 비워두면
/// 빌드 시 기본 문구가 채워지며, 스토어 심사에서 일반적으로 사유 부족
/// 거절 사유가 되므로 앱이 의미 있는 설명을 제공할 것을 권장한다.
import Foundation

public struct KSPermissionsConfig: Codable, Sendable, Equatable {
    /// 카메라 사용 (`NSCameraUsageDescription`, `device.camera`, MSIX `webcam`).
    public var camera: KSPermissionEntry

    /// 마이크 사용 (`NSMicrophoneUsageDescription`, `device.audio-input`, MSIX `microphone`).
    public var microphone: KSPermissionEntry

    /// 사진 라이브러리 접근 (iOS `NSPhotoLibraryUsageDescription` 등).
    public var photoLibrary: KSPermissionEntry

    /// 위치 정보 (`NSLocationWhenInUseUsageDescription`, MSIX `location`).
    public var location: KSPermissionEntry

    /// 외부 네트워크 서버로 들어오는 연결 수신(`network.server`).
    /// 일반 HTTP fetch 는 `security.http.allow` 가 자동으로 `network.client` 를
    /// 발급하므로 여기서 다시 설정할 필요 없다.
    public var networkServer: Bool

    public init(
        camera: KSPermissionEntry = .denied,
        microphone: KSPermissionEntry = .denied,
        photoLibrary: KSPermissionEntry = .denied,
        location: KSPermissionEntry = .denied,
        networkServer: Bool = false
    ) {
        self.camera = camera
        self.microphone = microphone
        self.photoLibrary = photoLibrary
        self.location = location
        self.networkServer = networkServer
    }

    /// 모든 권한 거부. 스토어 빌드 시 추가 entitlement / capability 가
    /// 발급되지 않는다.
    public static let denied = KSPermissionsConfig()

    private enum CodingKeys: String, CodingKey {
        case camera, microphone, photoLibrary, location, networkServer
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.camera = try c.decodeIfPresent(KSPermissionEntry.self, forKey: .camera) ?? .denied
        self.microphone =
            try c.decodeIfPresent(KSPermissionEntry.self, forKey: .microphone) ?? .denied
        self.photoLibrary =
            try c.decodeIfPresent(KSPermissionEntry.self, forKey: .photoLibrary) ?? .denied
        self.location =
            try c.decodeIfPresent(KSPermissionEntry.self, forKey: .location) ?? .denied
        self.networkServer = try c.decodeIfPresent(Bool.self, forKey: .networkServer) ?? false
    }
}

/// 권한 한 건의 활성화 여부와 사용자에게 표시될 사유 문자열.
///
/// 가장 흔한 두 형태를 모두 디코드한다:
///
/// 1. 단순 bool: `"camera": true` → `.granted(reason: nil)`
/// 2. 객체: `"camera": { "enabled": true, "reason": "..." }`
///
/// `.denied` 는 사용 사유와 무관하게 매니페스트/Info.plist 에 반영되지 않는다.
public struct KSPermissionEntry: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var reason: String?

    public init(enabled: Bool, reason: String? = nil) {
        self.enabled = enabled
        self.reason = reason
    }

    /// 권한 미사용. 매니페스트/plist 출력에서 제외된다.
    public static let denied = KSPermissionEntry(enabled: false, reason: nil)

    /// 권한 활성화. 사유 문자열이 없으면 빌드 시 기본 문구가 채워진다.
    public static func granted(reason: String? = nil) -> KSPermissionEntry {
        KSPermissionEntry(enabled: true, reason: reason)
    }

    public init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
            let flag = try? single.decode(Bool.self)
        {
            self.enabled = flag
            self.reason = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }

    private enum CodingKeys: String, CodingKey { case enabled, reason }
}
