/// Microsoft Store MSIX 패키저 (RFC-008 Phase 2).
///
/// 본 모듈은 **렌더링/계획 단계**를 순수 함수로 노출해 단위 테스트가 가능하게
/// 한다. 실제 `MakeAppx.exe pack` / `signtool.exe sign` 호출은 Windows 호스트에서만
/// `Shell.swell` 헬퍼로 수행한다.
///
/// 흐름:
///   1. `renderAppxManifest(_:)` 로 `AppxManifest.xml` 생성
///   2. `planMSIXPipeline(_:)` 로 `[MakeAppx pack, signtool sign?]` 시퀀스 산출
///   3. `executeMSIXSteps(_:dryRun:warnings:)` 로 실행 또는 dryrun 출력
///
/// Manifest 매핑 (RFC-008 §P2):
///   - `app.identifier`         → `<Identity Name>`
///   - `app.version`            → `<Identity Version>` (`x.y.z.0` 으로 정규화)
///   - `distribution.publisher` → `<Identity Publisher>` (CN= DN, 필수)
///   - `deepLink.schemes`       → `<uap:Extension Category="windows.protocol">`
///   - `autostart` 존재         → `<desktop:Extension Category="windows.startupTask">`
///   - WebView2 Evergreen       → `<PackageDependency Microsoft.WebView2RuntimeAnyVersion>`
///   - 기본                     → `<rescap:Capability Name="runFullTrust"/>` (Desktop Bridge)
public import Foundation
public import KalsaeCore

extension KSPackager {

    // MARK: - 입력값

    public enum MSIXArchitecture: String, Sendable, CaseIterable {
        case x64
        case x86
        case arm64

        /// AppxManifest `ProcessorArchitecture` attribute 값.
        public var manifestValue: String {
            switch self {
            case .x64: return "x64"
            case .x86: return "x86"
            case .arm64: return "arm64"
            }
        }
    }

    public struct MSIXInput: Sendable {
        public var appName: String
        public var version: String  // `x.y.z` — 자동으로 `x.y.z.0` 정규화
        public var identifier: String  // app.identifier
        /// AppxManifest `<Identity Publisher>` — `CN=...` 형태의 DN.
        /// Partner Center 에 등록된 CN 과 정확히 일치해야 한다.
        public var publisher: String
        /// `<DisplayName>` — 사람이 읽는 앱 이름. 기본은 `appName`.
        public var displayName: String
        public var publisherDisplayName: String
        public var description: String?
        public var architecture: MSIXArchitecture
        /// WebView2 Evergreen 정책이면 `<PackageDependency>` 가 추가된다.
        public var includesWebView2RuntimeDependency: Bool
        /// 등록할 URL 스킴. 비어있으면 `<uap:Extension>` 자체를 생략.
        public var deepLinkSchemes: [String]
        /// `nil` 이 아니면 `<desktop:Extension Category="windows.startupTask">` 추가.
        public var startupTaskID: String?
        public var startupTaskDisplayName: String?

        public init(
            appName: String,
            version: String,
            identifier: String,
            publisher: String,
            displayName: String? = nil,
            publisherDisplayName: String,
            description: String? = nil,
            architecture: MSIXArchitecture,
            includesWebView2RuntimeDependency: Bool,
            deepLinkSchemes: [String] = [],
            startupTaskID: String? = nil,
            startupTaskDisplayName: String? = nil
        ) {
            self.appName = appName
            self.version = version
            self.identifier = identifier
            self.publisher = publisher
            self.displayName = displayName ?? appName
            self.publisherDisplayName = publisherDisplayName
            self.description = description
            self.architecture = architecture
            self.includesWebView2RuntimeDependency = includesWebView2RuntimeDependency
            self.deepLinkSchemes = deepLinkSchemes
            self.startupTaskID = startupTaskID
            self.startupTaskDisplayName = startupTaskDisplayName
        }
    }

    // MARK: - 버전 정규화

    /// AppxManifest 의 `Version` attribute 는 `Major.Minor.Build.Revision`
    /// (정확히 4 octet, 각 octet 0-65535) 만 허용한다. SemVer 의 `1.2.3` 이나
    /// pre-release suffix (`1.2.3-rc1`) 를 받아 안전하게 4-octet 으로 변환한다.
    public static func normalizeMSIXVersion(_ raw: String) -> String {
        // pre-release / build metadata 절단 (`1.2.3-rc1+sha` → `1.2.3`).
        let core = raw.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? raw
        var parts = core.split(separator: ".").map(String.init)
        // 숫자가 아닌 토큰은 0 으로 치환.
        parts = parts.map { Int($0) != nil ? $0 : "0" }
        while parts.count < 4 { parts.append("0") }
        if parts.count > 4 { parts = Array(parts.prefix(4)) }
        return parts.joined(separator: ".")
    }

    // MARK: - AppxManifest.xml 렌더링

    /// XML 1.0 에서 attribute/text 에 등장하면 안 되는 5 문자를 이스케이프.
    private static func xmlEscape(_ s: String) -> String {
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

    public static func renderAppxManifest(_ input: MSIXInput) -> String {
        let normalizedVersion = normalizeMSIXVersion(input.version)
        let exeName = "\(input.appName).exe"

        var capabilities: [String] = [
            #"    <rescap:Capability Name="runFullTrust"/>"#
        ]
        // 기본 internetClient 권한 (HTTP 호출용). 매니페스트 capability 는 MSIX 에서
        // declared 만 되면 사용자 동의 prompt 가 따로 뜨지 않는다.
        capabilities.append(#"    <Capability Name="internetClient"/>"#)

        var dependencies: [String] = [
            #"    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.22631.0"/>"#
        ]
        if input.includesWebView2RuntimeDependency {
            dependencies.append(
                #"    <PackageDependency Name="Microsoft.WebView2RuntimeAnyVersion" Publisher="CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" MinVersion="0.0.0.0"/>"#
            )
        }

        var extensions: [String] = []
        if !input.deepLinkSchemes.isEmpty {
            // protocol extension 은 각 scheme 마다 별도 노드.
            for scheme in input.deepLinkSchemes {
                let safe = xmlEscape(scheme.lowercased())
                extensions.append(
                    """
                            <uap:Extension Category="windows.protocol">
                                <uap:Protocol Name="\(safe)">
                                    <uap:DisplayName>\(xmlEscape(input.displayName))</uap:DisplayName>
                                </uap:Protocol>
                            </uap:Extension>
                    """)
            }
        }
        if let taskID = input.startupTaskID {
            let label = input.startupTaskDisplayName ?? input.displayName
            extensions.append(
                """
                        <desktop:Extension Category="windows.startupTask" Executable="\(xmlEscape(exeName))" EntryPoint="Windows.FullTrustApplication">
                            <desktop:StartupTask TaskId="\(xmlEscape(taskID))" Enabled="false" DisplayName="\(xmlEscape(label))"/>
                        </desktop:Extension>
                """)
        }
        let extensionsBlock = extensions.isEmpty
            ? ""
            : "\n            <Extensions>\n\(extensions.joined(separator: "\n"))\n            </Extensions>"

        let descBlock = input.description.map { xmlEscape($0) } ?? xmlEscape(input.displayName)

        return """
            <?xml version="1.0" encoding="utf-8"?>
            <Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
                     xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
                     xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
                     xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10"
                     IgnorableNamespaces="uap rescap desktop">
                <Identity Name="\(xmlEscape(input.identifier))"
                          Publisher="\(xmlEscape(input.publisher))"
                          Version="\(normalizedVersion)"
                          ProcessorArchitecture="\(input.architecture.manifestValue)"/>
                <Properties>
                    <DisplayName>\(xmlEscape(input.displayName))</DisplayName>
                    <PublisherDisplayName>\(xmlEscape(input.publisherDisplayName))</PublisherDisplayName>
                    <Description>\(descBlock)</Description>
                    <Logo>Assets\\StoreLogo.png</Logo>
                </Properties>
                <Dependencies>
            \(dependencies.joined(separator: "\n"))
                </Dependencies>
                <Resources>
                    <Resource Language="en-us"/>
                </Resources>
                <Applications>
                    <Application Id="App" Executable="\(xmlEscape(exeName))" EntryPoint="Windows.FullTrustApplication">
                        <uap:VisualElements DisplayName="\(xmlEscape(input.displayName))"
                                            Description="\(descBlock)"
                                            BackgroundColor="transparent"
                                            Square150x150Logo="Assets\\Square150x150Logo.png"
                                            Square44x44Logo="Assets\\Square44x44Logo.png">
                            <uap:DefaultTile Wide310x150Logo="Assets\\Wide310x150Logo.png"/>
                            <uap:SplashScreen Image="Assets\\SplashScreen.png"/>
                        </uap:VisualElements>\(extensionsBlock)
                    </Application>
                </Applications>
                <Capabilities>
            \(capabilities.joined(separator: "\n"))
                </Capabilities>
            </Package>
            """
    }

    // MARK: - 명령 계획

    public struct MSIXPlanInput: Sendable {
        public var stagingDir: URL  // AppxManifest.xml + 페이로드가 든 디렉터리
        public var outputMSIX: URL  // 산출물 .msix
        /// `nil` 이면 sign 단계 생략.
        public var signtoolTemplate: String?

        public init(stagingDir: URL, outputMSIX: URL, signtoolTemplate: String?) {
            self.stagingDir = stagingDir
            self.outputMSIX = outputMSIX
            self.signtoolTemplate = signtoolTemplate
        }
    }

    public struct MSIXStep: Sendable, Equatable {
        public let label: String
        /// MakeAppx 는 인자 배열로, signtool 은 셸 템플릿으로 다루기 위해
        /// 둘 다 표현 가능한 형태로 둔다.
        public let command: String
        public let args: [String]
        /// signtool 처럼 `--signtool-cmd "signtool.exe sign /a {file}"` 템플릿이
        /// 통째로 셸을 거쳐 실행돼야 하면 `true`.
        public let viaShell: Bool

        public init(label: String, command: String, args: [String], viaShell: Bool = false) {
            self.label = label
            self.command = command
            self.args = args
            self.viaShell = viaShell
        }
    }

    public static func planMSIXPipeline(_ input: MSIXPlanInput) -> [MSIXStep] {
        var steps: [MSIXStep] = []
        steps.append(
            MSIXStep(
                label: "MakeAppx",
                command: "MakeAppx.exe",
                args: [
                    "pack",
                    "/d", input.stagingDir.path,
                    "/p", input.outputMSIX.path,
                    "/o",  // overwrite existing .msix
                ]))
        if let template = input.signtoolTemplate, !template.isEmpty {
            // `{file}` placeholder → outputMSIX path. 미치환 시 자동으로 끝에 추가.
            let expanded: String
            if template.contains("{file}") {
                expanded = template.replacingOccurrences(of: "{file}", with: "\"\(input.outputMSIX.path)\"")
            } else {
                expanded = "\(template) \"\(input.outputMSIX.path)\""
            }
            steps.append(
                MSIXStep(
                    label: "signtool",
                    command: expanded,
                    args: [],
                    viaShell: true))
        }
        return steps
    }

    // MARK: - 실행

    public static func executeMSIXSteps(
        _ steps: [MSIXStep],
        dryRun: Bool,
        warnings: inout [String]
    ) throws {
        if dryRun {
            for s in steps { print("  • \(s.label): \(s.command) \(s.args.joined(separator: " "))") }
            return
        }
        #if os(Windows)
            for s in steps {
                print("  ▶ \(s.label)")
                if s.viaShell {
                    try shell(commandLine: s.command)
                } else {
                    try shell(command: s.command, arguments: s.args)
                }
            }
        #else
            for s in steps { print("  • \(s.label): \(s.command) \(s.args.joined(separator: " "))") }
            warnings.append("MSIX packaging skipped on non-Windows host. Run on Windows to actually produce a .msix.")
        #endif
    }
}
