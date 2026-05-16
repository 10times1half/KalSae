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
        append(
            "NSCameraUsageDescription", permissions.camera,
            "This app uses the camera.")
        append(
            "NSMicrophoneUsageDescription", permissions.microphone,
            "This app uses the microphone.")
        append(
            "NSPhotoLibraryUsageDescription", permissions.photoLibrary,
            "This app accesses your photo library.")
        append(
            "NSLocationWhenInUseUsageDescription", permissions.location,
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

// MARK: - iOS .app 번들 패키저 (Phase iOS-Stable §3)
//
// 데스크톱 패키저(`KSPackager.run`) / Android 패키저(`KSPackager.runAndroid`) 와
// 동일한 5-OS 표면을 제공하는 미니멀 .app 번들 emitter.
//
// 디렉터리 구조 (Android 와 동일한 "frontend at root + kalsae.json + native exe" 패턴):
//   <output>/<AppName>.app/
//     Info.plist                       (NSAllowsArbitraryLoads=false, MinimumOSVersion=16.0)
//     <executableName>                 (cross-compiled iOS binary)
//     kalsae.json                      (sanitized: frontendDist=".", devtools=false)
//     <frontend dist contents>...      (HTML/JS/CSS at .app root)
//     Icon.png                         (옵션, CFBundleIconFile)
//
// 호스트 OS 무관 (순수 string emit). 실제 실행은 `xcrun simctl install` /
// 디바이스 설치 / TestFlight 단계로 분리.
extension KSPackager {

    public enum IOSArchitecture: String, Sendable, CaseIterable {
        case arm64 = "arm64"
        case arm64Simulator = "arm64-simulator"
    }

    public struct IOSOptions: Sendable {
        /// 빌드된 iOS 실행 파일 (Mach-O). swift build --triple arm64-apple-ios16.0 산출물.
        public var executablePath: URL
        public var configPath: URL
        public var frontendDist: URL?
        public var output: URL
        public var appName: String
        public var version: String
        /// CFBundleIdentifier (역도메인). 예: `com.example.myapp`.
        public var identifier: String
        public var bundleVersion: String
        public var minimumOSVersion: String
        public var architecture: IOSArchitecture
        public var iconPath: URL?
        /// 딥 링크 스키들 (kalsae.json `deepLink.schemes`). CFBundleURLTypes.
        public var deepLinkSchemes: [String]
        public var stripSourceMaps: Bool
        public var stripExtensions: [String]
        /// permissions → NS*UsageDescription 변환에 사용. nil 이면 생략.
        public var permissions: KSPermissionsConfig?

        public init(
            executablePath: URL,
            configPath: URL,
            frontendDist: URL?,
            output: URL,
            appName: String,
            version: String,
            identifier: String,
            bundleVersion: String = "1",
            minimumOSVersion: String = "16.0",
            architecture: IOSArchitecture = .arm64,
            iconPath: URL? = nil,
            deepLinkSchemes: [String] = [],
            stripSourceMaps: Bool = true,
            stripExtensions: [String] = [],
            permissions: KSPermissionsConfig? = nil
        ) {
            self.executablePath = executablePath
            self.configPath = configPath
            self.frontendDist = frontendDist
            self.output = output
            self.appName = appName
            self.version = version
            self.identifier = identifier
            self.bundleVersion = bundleVersion
            self.minimumOSVersion = minimumOSVersion
            self.architecture = architecture
            self.iconPath = iconPath
            self.deepLinkSchemes = deepLinkSchemes
            self.stripSourceMaps = stripSourceMaps
            self.stripExtensions = stripExtensions
            self.permissions = permissions
        }
    }

    /// iOS .app 번들을 emit한다. 호스트 OS 무관 — 실제 디바이스 실행/시뮬레이터
    /// 설치는 macOS + Xcode 가 필요하다.
    public static func runIOS(_ opts: IOSOptions) throws -> Report {
        let fm = FileManager.default
        var warnings: [String] = []

        // 0) 검증
        guard fm.fileExists(atPath: opts.executablePath.path) else {
            throw KSError(
                code: .configInvalid,
                message: "iOS executable not found at \(opts.executablePath.path). "
                    + "Build it first with: "
                    + "swift build --triple arm64-apple-ios\(opts.minimumOSVersion) "
                    + "-c release --product <YourApp>")
        }
        guard isValidIOSBundleIdentifier(opts.identifier) else {
            throw KSError(
                code: .configInvalid,
                message: "iOS CFBundleIdentifier '\(opts.identifier)' is invalid. "
                    + "Must be reverse-DNS, e.g. com.example.myapp.")
        }

        // 1) 출력 디렉터리 (clean rebuild)
        if fm.fileExists(atPath: opts.output.path) {
            try retryingTransient { try fm.removeItem(at: opts.output) }
        }
        try fm.createDirectory(at: opts.output, withIntermediateDirectories: true)

        let appBundle = opts.output.appendingPathComponent("\(opts.appName).app")
        try fm.createDirectory(at: appBundle, withIntermediateDirectories: true)

        // 2) 실행 파일
        let exeName = sanitizedExecutableName(opts.appName)
        let dstExe = appBundle.appendingPathComponent(exeName)
        try safeCopy(from: opts.executablePath, to: dstExe, fm: fm)
        #if os(macOS) || os(Linux)
            // 실행 비트 보존 (Windows 호스트는 chmod 무의미).
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstExe.path)
        #endif

        // 3) Info.plist
        let infoPlist = renderIOSInfoPlist(opts: opts, executableName: exeName)
        try infoPlist.write(
            to: appBundle.appendingPathComponent("Info.plist"),
            atomically: true, encoding: .utf8)

        // 4) kalsae.json — frontendDist=".", devtools off (Android 와 동일).
        let dstConfig = appBundle.appendingPathComponent("kalsae.json")
        try safeCopy(from: opts.configPath, to: dstConfig, fm: fm)
        try rewritePackagedConfig(at: dstConfig, frontendDist: ".", disableDevtools: true)

        // 5) Frontend dist → .app 루트 (Android 와 동일 패턴, frontendDist=".")
        if let dist = opts.frontendDist, fm.fileExists(atPath: dist.path) {
            try copyIOSDistContents(of: dist, into: appBundle, fm: fm)
            let strip = KSBundleAnalyzer.strip(
                distURL: appBundle,
                stripSourceMaps: opts.stripSourceMaps,
                stripExtensions: opts.stripExtensions)
            if strip.removed > 0 {
                print(
                    "  🗑  Stripped \(strip.removed) file(s) "
                        + "(\(KSBundleReport.formatBytes(strip.savedBytes)))")
            }
            if strip.failed > 0 {
                warnings.append(
                    "Failed to strip \(strip.failed) file(s) from frontend bundle.")
            }
        } else {
            warnings.append(
                "Frontend dist directory not found; .app will have no web assets.")
        }

        // 6) 아이콘 (옵션). 단일 PNG 만 지원 — 정식 .car 자산 카탈로그가
        // 필요한 경우 호출자가 macOS 에서 actool 후처리.
        if let icon = opts.iconPath, fm.fileExists(atPath: icon.path) {
            let dstIcon = appBundle.appendingPathComponent("Icon.png")
            try safeCopy(from: icon, to: dstIcon, fm: fm)
        } else {
            warnings.append(
                "No icon provided; .app will use the system default. "
                    + "Pass iconPath for production builds.")
        }

        // 7) 호스트 OS 경고 (실제 실행 환경 안내)
        #if !os(macOS)
            warnings.append(
                "Emitted .app bundle on non-macOS host. To run it use macOS + Xcode "
                    + "(e.g. `xcrun simctl install booted <bundle>` for the simulator).")
        #endif

        return Report(
            outputPath: appBundle.path,
            zipPath: nil,
            policy: "ios-app-bundle",
            warnings: warnings,
            standalone: nil)
    }

    // MARK: - 내부 helper

    /// 역도메인 형식 검증. 점으로 구분된 2개 이상의 세그먼트, 각 세그먼트는
    /// 영문/숫자/하이픈 (Apple 가이드라인). 시작/끝 하이픈 금지.
    static func isValidIOSBundleIdentifier(_ id: String) -> Bool {
        let segs = id.split(separator: ".", omittingEmptySubsequences: false)
        guard segs.count >= 2 else { return false }
        for seg in segs {
            guard !seg.isEmpty else { return false }
            if seg.first == "-" || seg.last == "-" { return false }
            for ch in seg {
                if ch.isLetter || ch.isNumber || ch == "-" { continue }
                return false
            }
        }
        return true
    }

    /// CFBundleExecutable 은 공백/특수문자 금지. AppName 을 안전화.
    static func sanitizedExecutableName(_ appName: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let mapped = appName.map { allowed.contains($0) ? $0 : "_" }
        let result = String(mapped)
        return result.isEmpty ? "App" : result
    }

    /// dist 의 *내용* 을 dst 에 복사한다 (dist 자체 디렉터리 X). Android 패키저의
    /// `copyDistContents` 와 동일한 시맨틱이지만 iOS 는 `Info.plist` /
    /// `kalsae.json` 등 .app 루트 파일과 충돌하지 않도록 동일 이름은 덮어쓰기
    /// 전에 경고 (방어).
    static func copyIOSDistContents(of src: URL, into dst: URL, fm: FileManager) throws {
        let entries = try fm.contentsOfDirectory(atPath: src.path)
        for name in entries {
            let s = src.appendingPathComponent(name)
            let d = dst.appendingPathComponent(name)
            if fm.fileExists(atPath: d.path) {
                try retryingTransient { try fm.removeItem(at: d) }
            }
            try retryingTransient { try fm.copyItem(at: s, to: d) }
        }
    }

    static func renderIOSInfoPlist(opts: IOSOptions, executableName: String) -> String {
        var entries: [String] = []
        func kv(_ k: String, _ v: String, raw: Bool = false) {
            entries.append("    <key>\(k)</key>")
            entries.append(
                raw ? "    \(v)" : "    <string>\(xmlEscapeIOSPlist(v))</string>")
        }

        kv("CFBundleDevelopmentRegion", "en")
        kv("CFBundleDisplayName", opts.appName)
        kv("CFBundleExecutable", executableName)
        kv("CFBundleIdentifier", opts.identifier)
        kv("CFBundleInfoDictionaryVersion", "6.0")
        kv("CFBundleName", opts.appName)
        kv("CFBundlePackageType", "APPL")
        kv("CFBundleShortVersionString", opts.version)
        kv("CFBundleVersion", opts.bundleVersion)
        kv("MinimumOSVersion", opts.minimumOSVersion)
        kv("LSRequiresIPhoneOS", "<true/>", raw: true)

        // CFBundleSupportedPlatforms
        entries.append("    <key>CFBundleSupportedPlatforms</key>")
        entries.append("    <array>")
        let platform =
            opts.architecture == .arm64Simulator ? "iPhoneSimulator" : "iPhoneOS"
        entries.append("        <string>\(platform)</string>")
        entries.append("    </array>")

        // UIDeviceFamily: 1=iPhone, 2=iPad
        entries.append("    <key>UIDeviceFamily</key>")
        entries.append("    <array>")
        entries.append("        <integer>1</integer>")
        entries.append("        <integer>2</integer>")
        entries.append("    </array>")

        // 지원 인터페이스 방향 (기본 portrait + landscape 양쪽).
        entries.append("    <key>UISupportedInterfaceOrientations</key>")
        entries.append("    <array>")
        entries.append("        <string>UIInterfaceOrientationPortrait</string>")
        entries.append("        <string>UIInterfaceOrientationLandscapeLeft</string>")
        entries.append("        <string>UIInterfaceOrientationLandscapeRight</string>")
        entries.append("    </array>")

        // 보안: ATS 강제 (RFC-008 §4.2). iOS 9+ 의 NSAppTransportSecurity 의 기본값
        // 은 이미 secure 이지만 명시적으로 NSAllowsArbitraryLoads=false 를 박는다.
        entries.append("    <key>NSAppTransportSecurity</key>")
        entries.append("    <dict>")
        entries.append("        <key>NSAllowsArbitraryLoads</key>")
        entries.append("        <false/>")
        entries.append("    </dict>")

        // UILaunchScreen — iOS 14+ 의 LaunchScreen.storyboard 대체 dictionary.
        entries.append("    <key>UILaunchScreen</key>")
        entries.append("    <dict/>")

        // 아이콘 (단일 PNG). 자산 카탈로그 사용 시 호출자가 별도 처리.
        if opts.iconPath != nil {
            kv("CFBundleIconFile", "Icon.png")
        }

        // 딥 링크 스킴.
        if !opts.deepLinkSchemes.isEmpty {
            entries.append("    <key>CFBundleURLTypes</key>")
            entries.append("    <array>")
            entries.append("        <dict>")
            entries.append("            <key>CFBundleURLName</key>")
            entries.append(
                "            <string>\(xmlEscapeIOSPlist(opts.identifier))</string>")
            entries.append("            <key>CFBundleURLSchemes</key>")
            entries.append("            <array>")
            for scheme in opts.deepLinkSchemes {
                entries.append(
                    "                <string>\(xmlEscapeIOSPlist(scheme))</string>")
            }
            entries.append("            </array>")
            entries.append("        </dict>")
            entries.append("    </array>")
        }

        // permissions → NS*UsageDescription
        if let perms = opts.permissions {
            let usageBlock = renderIOSUsageDescriptions(perms)
            if !usageBlock.isEmpty {
                // 결과는 이미 <key>...</key><string>...</string> 쌍. 4-space 들여쓰기로
                // 정렬해 plist body 에 합류.
                for line in usageBlock.split(separator: "\n") {
                    entries.append("    \(line)")
                }
            }
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
}
