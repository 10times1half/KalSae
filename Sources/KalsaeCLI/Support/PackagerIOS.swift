/// iOS App Store 패키징 파이프라인 (RFC-008 Phase 4).
///
/// SwiftPM 단독으로는 IPA 를 만들 수 없으므로 본 모듈은
/// `xcodebuild archive` → `xcodebuild -exportArchive` → `xcrun altool` 의
/// 3 단계를 순수 명령 시퀀스로 계산한다.
///
/// 호출자는 다음 중 하나를 제공해야 한다:
///   * 사용자 정의 `.xcodeproj` 또는 `.xcworkspace` 경로 (`projectPath`/`workspacePath`)
///   * + 빌드 스킴 (`scheme`)
///
/// 자동 .xcodeproj 생성은 v0.x 범위 밖 — SwiftPM Xcode 프로젝트 생성을
/// 이용하더라도 자산 카탈로그/Info.plist 가 사용자 책임이기 때문이다.
///
/// 단계별 명령:
///   1. `xcodebuild archive` (스킴, configuration=Release, 자동 서명/수동 서명)
///   2. `xcodebuild -exportArchive -exportOptionsPlist`
///      → 산출 `.ipa` 가 `exportPath/<AppName>.ipa`
///   3. (선택) `xcrun altool --upload-app -f <.ipa> --apiKey ... --apiIssuer ...`
///
/// `executeIOSSteps` 는 macOS 호스트에서만 실제 실행하며, 그 외 호스트는
/// 출력만 하고 `warnings` 에 기록한다.
public import Foundation
public import KalsaeCore

extension KSPackager {

    /// iOS 빌드 시 사용할 Xcode 프로젝트 종류.
    public enum IOSProjectKind: Sendable, Equatable {
        case xcodeproj(URL)
        case xcworkspace(URL)
    }

    /// `exportOptions.plist` 의 `method` 값. App Store 업로드는 `app-store-connect`
    /// (Xcode 15+) 또는 레거시 `app-store`. Ad-hoc/Enterprise/Development 도 지원.
    public enum IOSExportMethod: String, Sendable, Equatable {
        case appStoreConnect = "app-store-connect"
        case appStore = "app-store"
        case adHoc = "ad-hoc"
        case enterprise = "enterprise"
        case development = "development"
    }

    /// iOS 패키징 입력값.
    public struct IOSPackagingInput: Sendable {
        public var project: IOSProjectKind
        public var scheme: String
        public var configuration: String  // 일반적으로 "Release"
        public var archivePath: URL  // <build>/<App>.xcarchive
        public var exportPath: URL  // <build>/export
        public var exportOptionsPlist: URL
        public var ipaOutput: URL  // <build>/export/<App>.ipa (xcodebuild 가 결정)
        public var teamID: String
        public var bundleIdentifier: String
        public var exportMethod: IOSExportMethod

        /// `xcrun altool --upload-app` 옵션. 모두 제공된 경우에만 업로드 단계가
        /// 시퀀스에 포함된다.
        public var appStoreConnectAPIKeyID: String?
        public var appStoreConnectAPIIssuerID: String?

        /// 수동 서명 시 codesign identity. nil 이면 Xcode 자동 서명.
        public var codeSignIdentity: String?
        public var provisioningProfileSpecifier: String?

        public init(
            project: IOSProjectKind,
            scheme: String,
            configuration: String = "Release",
            archivePath: URL,
            exportPath: URL,
            exportOptionsPlist: URL,
            ipaOutput: URL,
            teamID: String,
            bundleIdentifier: String,
            exportMethod: IOSExportMethod = .appStoreConnect,
            appStoreConnectAPIKeyID: String? = nil,
            appStoreConnectAPIIssuerID: String? = nil,
            codeSignIdentity: String? = nil,
            provisioningProfileSpecifier: String? = nil
        ) {
            self.project = project
            self.scheme = scheme
            self.configuration = configuration
            self.archivePath = archivePath
            self.exportPath = exportPath
            self.exportOptionsPlist = exportOptionsPlist
            self.ipaOutput = ipaOutput
            self.teamID = teamID
            self.bundleIdentifier = bundleIdentifier
            self.exportMethod = exportMethod
            self.appStoreConnectAPIKeyID = appStoreConnectAPIKeyID
            self.appStoreConnectAPIIssuerID = appStoreConnectAPIIssuerID
            self.codeSignIdentity = codeSignIdentity
            self.provisioningProfileSpecifier = provisioningProfileSpecifier
        }
    }

    // MARK: - Plan (pure)

    /// archive → exportArchive → (옵션) altool upload 명령 시퀀스를 빌드한다.
    public static func planIOSPackagingPipeline(_ input: IOSPackagingInput) -> [MacSignStep] {
        var steps: [MacSignStep] = []

        // (1) xcodebuild archive
        var archiveArgs: [String] = []
        switch input.project {
        case .xcodeproj(let url):
            archiveArgs += ["-project", url.path]
        case .xcworkspace(let url):
            archiveArgs += ["-workspace", url.path]
        }
        archiveArgs += [
            "-scheme", input.scheme,
            "-configuration", input.configuration,
            "-destination", "generic/platform=iOS",
            "-archivePath", input.archivePath.path,
            "archive",
            "DEVELOPMENT_TEAM=\(input.teamID)",
            "PRODUCT_BUNDLE_IDENTIFIER=\(input.bundleIdentifier)",
        ]
        if let identity = input.codeSignIdentity, !identity.isEmpty {
            archiveArgs += [
                "CODE_SIGN_STYLE=Manual",
                "CODE_SIGN_IDENTITY=\(identity)",
            ]
            if let profile = input.provisioningProfileSpecifier, !profile.isEmpty {
                archiveArgs += ["PROVISIONING_PROFILE_SPECIFIER=\(profile)"]
            }
        }
        steps.append(.init(command: "xcodebuild", args: archiveArgs, label: "archive"))

        // (2) xcodebuild -exportArchive
        let exportArgs: [String] = [
            "-exportArchive",
            "-archivePath", input.archivePath.path,
            "-exportOptionsPlist", input.exportOptionsPlist.path,
            "-exportPath", input.exportPath.path,
        ]
        steps.append(.init(command: "xcodebuild", args: exportArgs, label: "exportArchive"))

        // (3) altool upload (모든 자격증명 제공 시에만)
        if let keyID = input.appStoreConnectAPIKeyID,
            let issuerID = input.appStoreConnectAPIIssuerID,
            !keyID.isEmpty, !issuerID.isEmpty,
            input.exportMethod == .appStoreConnect || input.exportMethod == .appStore
        {
            let altoolArgs: [String] = [
                "altool", "--upload-app",
                "--type", "ios",
                "-f", input.ipaOutput.path,
                "--apiKey", keyID,
                "--apiIssuer", issuerID,
            ]
            steps.append(.init(command: "xcrun", args: altoolArgs, label: "upload"))
        }

        return steps
    }

    // MARK: - exportOptions.plist 렌더러 (pure)

    /// `xcodebuild -exportArchive -exportOptionsPlist` 가 읽어야 할 plist 를 렌더한다.
    public static func renderIOSExportOptionsPlist(
        method: IOSExportMethod,
        teamID: String,
        bundleIdentifier: String,
        provisioningProfileName: String? = nil,
        signingStyle: String = "automatic",
        uploadSymbols: Bool = true
    ) -> String {
        var entries: [String] = []
        entries.append("    <key>method</key>")
        entries.append("    <string>\(method.rawValue)</string>")
        entries.append("    <key>teamID</key>")
        entries.append("    <string>\(teamID)</string>")
        entries.append("    <key>signingStyle</key>")
        entries.append("    <string>\(signingStyle)</string>")
        entries.append("    <key>uploadSymbols</key>")
        entries.append(uploadSymbols ? "    <true/>" : "    <false/>")
        entries.append("    <key>compileBitcode</key>")
        entries.append("    <false/>")

        if signingStyle == "manual", let profile = provisioningProfileName, !profile.isEmpty {
            entries.append("    <key>provisioningProfiles</key>")
            entries.append("    <dict>")
            entries.append("        <key>\(bundleIdentifier)</key>")
            entries.append("        <string>\(profile)</string>")
            entries.append("    </dict>")
        }

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            \(entries.joined(separator: "\n"))
            </dict>
            </plist>
            """
    }

    // MARK: - Info.plist 보강 (permissions → NS*UsageDescription) (pure)

    /// `KSPermissionsConfig` 를 iOS Info.plist 의 `NS*UsageDescription` 키로 변환한다.
    /// 결과는 `<key>...</key><string>...</string>` 쌍이 담긴 plain text — 호출자가
    /// 기존 plist 에 머지하거나 단독 plist 로 쓸 수 있다.
    public static func renderIOSUsageDescriptions(
        _ permissions: KSPermissionsConfig
    ) -> String {
        var lines: [String] = []
        func append(_ key: String, _ entry: KSPermissionEntry, _ defaultReason: String) {
            guard entry.enabled else { return }
            let reason = entry.reason ?? defaultReason
            lines.append("<key>\(key)</key>")
            lines.append("<string>\(xmlEscapeIOSPlist(reason))</string>")
        }
        append("NSCameraUsageDescription", permissions.camera,
            "This app uses the camera.")
        append("NSMicrophoneUsageDescription", permissions.microphone,
            "This app uses the microphone.")
        append("NSPhotoLibraryUsageDescription", permissions.photoLibrary,
            "This app accesses your photo library.")
        append("NSLocationWhenInUseUsageDescription", permissions.location,
            "This app uses your location while in use.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Executor (macOS-only)

    public static func executeIOSSteps(
        _ steps: [MacSignStep],
        dryRun: Bool,
        warnings: inout [String]
    ) throws {
        #if os(macOS)
            if dryRun {
                printIOSPlanned(steps)
                return
            }
            for step in steps {
                print("  ▶ \(step.label): \(step.command) \(step.args.joined(separator: " "))")
                try shell(command: step.command, arguments: step.args)
            }
        #else
            printIOSPlanned(steps)
            if !dryRun {
                warnings.append(
                    "iOS packaging pipeline skipped on non-macOS host. "
                    + "Re-run `kalsae build --store ios-appstore` on macOS with Xcode installed.")
            }
        #endif
    }

    private static func printIOSPlanned(_ steps: [MacSignStep]) {
        for step in steps {
            print("  • \(step.label): \(step.command) \(step.args.joined(separator: " "))")
        }
    }
}

@inline(__always)
private func xmlEscapeIOSPlist(_ s: String) -> String {
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
