import Foundation
public import KalsaeCore

// MARK: - Entitlements 생성기 (RFC-008 P3 — Mac App Store / Developer ID)
//
// `Kalsae.json`(`KSConfig`) → macOS/iOS `.entitlements` plist 의 자동 매핑.
//
// **순수 함수**: 파일/네트워크 I/O 없음. `renderEntitlementsPlist(_:target:)` 는
// 입력만으로 결과 XML 문자열을 생성하며 단위 테스트 가능하다.
//
// 매핑 규약 (AGENTS.md §Phase 3 표 참조):
// - 항상: `app-sandbox=true` (MAS), `cs.allow-jit=true` (WKWebView)
// - `application-identifier`, `team-identifier`: distribution 메타에서 주입
// - `security.http.allow` 비어있지 않음 → `network.client`
// - `permissions.networkServer=true` → `network.server`
// - 다이얼로그(항상 가정) → `files.user-selected.read-write`
// - `permissions.camera/microphone/photoLibrary/location` → 대응 device entitlement
//
// Developer ID(non-MAS) 빌드는 `app-sandbox` 를 생략하고 `cs.allow-jit` 만 발급.

/// 진입 인자. 모든 필드가 testable 하도록 외부 의존성을 받지 않는다.
public struct EntitlementsInput: Sendable, Equatable {
    /// 빌드 대상. MAS 가 아니면 sandbox/application-identifier 가 빠진다.
    public var target: KSDistributionTarget

    /// MAS `application-identifier`(예: `ABCDE12345.app.kalsae.demo`).
    /// `target == .macAppStore` 이고 nil 이면 호출자가 책임지고 검증해야 한다.
    public var applicationIdentifier: String?

    /// Apple Team ID(예: `ABCDE12345`).
    public var teamIdentifier: String?

    /// `security.http.allow` 비어있지 않음 → `network.client` 발급.
    public var allowOutboundHTTP: Bool

    /// `permissions.networkServer=true` → `network.server` 발급.
    public var allowIncomingNetwork: Bool

    /// `permissions.camera.enabled`. true 면 `device.camera`.
    public var requiresCamera: Bool

    /// `permissions.microphone.enabled`. true 면 `device.audio-input`.
    public var requiresMicrophone: Bool

    /// `permissions.photoLibrary.enabled`. true 면
    /// `personal-information.photos-library`(MAS read-only).
    public var requiresPhotoLibrary: Bool

    /// `permissions.location.enabled`. true 면 `personal-information.location`.
    public var requiresLocation: Bool

    /// 다이얼로그(파일 열기/저장) 사용 여부. 거의 모든 앱이 사용한다고 가정하고
    /// 기본 true. MAS 에서 sandbox 사용 시 필수.
    public var usesFileDialogs: Bool

    public init(
        target: KSDistributionTarget,
        applicationIdentifier: String? = nil,
        teamIdentifier: String? = nil,
        allowOutboundHTTP: Bool = false,
        allowIncomingNetwork: Bool = false,
        requiresCamera: Bool = false,
        requiresMicrophone: Bool = false,
        requiresPhotoLibrary: Bool = false,
        requiresLocation: Bool = false,
        usesFileDialogs: Bool = true
    ) {
        self.target = target
        self.applicationIdentifier = applicationIdentifier
        self.teamIdentifier = teamIdentifier
        self.allowOutboundHTTP = allowOutboundHTTP
        self.allowIncomingNetwork = allowIncomingNetwork
        self.requiresCamera = requiresCamera
        self.requiresMicrophone = requiresMicrophone
        self.requiresPhotoLibrary = requiresPhotoLibrary
        self.requiresLocation = requiresLocation
        self.usesFileDialogs = usesFileDialogs
    }
}

/// `KSConfig` + 배포 메타로부터 `EntitlementsInput` 을 derive 한다.
///
/// CLI 가 `--store mas` 와 함께 `config.distribution.appleTeamID` /
/// `config.app.identifier` 를 결합해 호출한다.
public func makeEntitlementsInput(
    config: KSConfig,
    target: KSDistributionTarget,
    applicationIdentifier: String? = nil
) -> EntitlementsInput {
    let teamID = config.distribution.appleTeamID
    let bundle = config.app.identifier
    let derivedAppID: String?
    if target == .macAppStore || target == .iosAppStore {
        if let explicit = applicationIdentifier {
            derivedAppID = explicit
        } else if let team = teamID, !team.isEmpty {
            derivedAppID = "\(team).\(bundle)"
        } else {
            derivedAppID = nil
        }
    } else {
        derivedAppID = nil
    }

    return EntitlementsInput(
        target: target,
        applicationIdentifier: derivedAppID,
        teamIdentifier: teamID,
        allowOutboundHTTP: !config.security.http.allow.isEmpty,
        allowIncomingNetwork: config.permissions.networkServer,
        requiresCamera: config.permissions.camera.enabled,
        requiresMicrophone: config.permissions.microphone.enabled,
        requiresPhotoLibrary: config.permissions.photoLibrary.enabled,
        requiresLocation: config.permissions.location.enabled,
        usesFileDialogs: true
    )
}

/// `.entitlements` XML(plist) 을 렌더한다. 결과 문자열은 `codesign --entitlements`
/// 에 바로 전달할 수 있다.
public func renderEntitlementsPlist(_ input: EntitlementsInput) -> String {
    var lines: [String] = []
    lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    lines.append(
        "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
            + "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">")
    lines.append("<plist version=\"1.0\">")
    lines.append("<dict>")

    func appendBool(_ key: String, _ value: Bool) {
        lines.append("    <key>\(key)</key>")
        lines.append(value ? "    <true/>" : "    <false/>")
    }
    func appendString(_ key: String, _ value: String) {
        lines.append("    <key>\(key)</key>")
        lines.append("    <string>\(xmlEscapeEntitlements(value))</string>")
    }

    // 1. WKWebView 의 JIT(JavaScriptCore) 가 sandbox/Hardened Runtime 양쪽에서
    //    필요로 하는 entitlement. 항상 발급.
    appendBool("com.apple.security.cs.allow-jit", true)

    // 2. App Sandbox — MAS 필수, Developer ID 에서는 발급하지 않음.
    if input.target.requiresAppSandbox {
        appendBool("com.apple.security.app-sandbox", true)
    }

    // 3. MAS 식별자. iOS 도 동일 키 사용.
    if input.target == .macAppStore || input.target == .iosAppStore {
        if let appID = input.applicationIdentifier {
            appendString("application-identifier", appID)
        }
        if let team = input.teamIdentifier {
            appendString("com.apple.developer.team-identifier", team)
        }
    }

    // 4. 네트워크.
    if input.allowOutboundHTTP {
        appendBool("com.apple.security.network.client", true)
    }
    if input.allowIncomingNetwork {
        appendBool("com.apple.security.network.server", true)
    }

    // 5. 다이얼로그(NSOpenPanel/NSSavePanel)는 MAS sandbox 에서 user-selected
    //    파일 접근 entitlement 가 있어야 사용자가 고른 경로를 읽고 쓸 수 있다.
    if input.target.requiresAppSandbox && input.usesFileDialogs {
        appendBool("com.apple.security.files.user-selected.read-write", true)
    }

    // 6. Device permissions. iOS/MAS 양쪽에서 동일 키.
    if input.requiresCamera {
        appendBool("com.apple.security.device.camera", true)
    }
    if input.requiresMicrophone {
        appendBool("com.apple.security.device.audio-input", true)
    }
    if input.requiresPhotoLibrary {
        appendBool(
            "com.apple.security.personal-information.photos-library", true)
    }
    if input.requiresLocation {
        appendBool("com.apple.security.personal-information.location", true)
    }

    lines.append("</dict>")
    lines.append("</plist>")
    return lines.joined(separator: "\n") + "\n"
}

@inline(__always)
private func xmlEscapeEntitlements(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        case "'": out += "&apos;"
        default: out.append(ch)
        }
    }
    return out
}
