import Foundation
import Testing

@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("KSPackager MSIX manifest + plan (RFC-008 P2)")
struct PackagerMSIXTests {

    private func makeInput(
        version: String = "1.2.3",
        deepLink: [String] = [],
        startup: String? = nil,
        wv2: Bool = true,
        publisher: String = "CN=Acme Inc, O=Acme Inc, L=Seoul, C=KR"
    ) -> KSPackager.MSIXInput {
        return .init(
            appName: "Kalsae Demo",
            version: version,
            identifier: "dev.kalsae.demo",
            publisher: publisher,
            displayName: "Kalsae Demo",
            publisherDisplayName: "Acme Inc",
            description: "Sample app",
            architecture: .x64,
            includesWebView2RuntimeDependency: wv2,
            deepLinkSchemes: deepLink,
            startupTaskID: startup,
            startupTaskDisplayName: startup.map { _ in "Kalsae Demo (auto)" })
    }

    // MARK: - Version normalization

    @Test("normalizeMSIXVersion pads 3-octet SemVer to 4 octets")
    func versionPadsTo4() {
        #expect(KSPackager.normalizeMSIXVersion("1.2.3") == "1.2.3.0")
        #expect(KSPackager.normalizeMSIXVersion("1.0") == "1.0.0.0")
        #expect(KSPackager.normalizeMSIXVersion("9") == "9.0.0.0")
    }

    @Test("normalizeMSIXVersion strips pre-release and metadata")
    func versionStripsSuffix() {
        #expect(KSPackager.normalizeMSIXVersion("1.2.3-rc1") == "1.2.3.0")
        #expect(KSPackager.normalizeMSIXVersion("1.2.3+sha.abc") == "1.2.3.0")
        #expect(KSPackager.normalizeMSIXVersion("1.2.3-rc1+meta") == "1.2.3.0")
    }

    @Test("normalizeMSIXVersion truncates beyond 4 octets")
    func versionTruncates() {
        #expect(KSPackager.normalizeMSIXVersion("1.2.3.4.5") == "1.2.3.4")
    }

    @Test("normalizeMSIXVersion replaces non-numeric tokens with 0")
    func versionNonNumeric() {
        #expect(KSPackager.normalizeMSIXVersion("1.alpha.3") == "1.0.3.0")
    }

    // MARK: - Manifest rendering

    @Test("Identity block carries all required attributes")
    func identityAttributes() {
        let xml = KSPackager.renderAppxManifest(makeInput())
        #expect(xml.contains(#"Name="dev.kalsae.demo""#))
        #expect(xml.contains(#"Publisher="CN=Acme Inc, O=Acme Inc, L=Seoul, C=KR""#))
        #expect(xml.contains(#"Version="1.2.3.0""#))
        #expect(xml.contains(#"ProcessorArchitecture="x64""#))
    }

    @Test("Default manifest always includes runFullTrust restricted capability")
    func runFullTrustCapability() {
        let xml = KSPackager.renderAppxManifest(makeInput())
        #expect(xml.contains(#"<rescap:Capability Name="runFullTrust"/>"#))
    }

    @Test("Manifest references TargetDeviceFamily=Windows.Desktop")
    func targetDeviceFamily() {
        let xml = KSPackager.renderAppxManifest(makeInput())
        #expect(xml.contains(#"<TargetDeviceFamily Name="Windows.Desktop""#))
    }

    @Test("WebView2 PackageDependency emitted only when requested")
    func webView2DependencyToggle() {
        let xmlOn = KSPackager.renderAppxManifest(makeInput(wv2: true))
        #expect(xmlOn.contains("Microsoft.WebView2RuntimeAnyVersion"))

        let xmlOff = KSPackager.renderAppxManifest(makeInput(wv2: false))
        #expect(xmlOff.contains("Microsoft.WebView2RuntimeAnyVersion") == false)
    }

    @Test("Deep-link schemes emit one uap:Extension per scheme")
    func deepLinkSchemes() {
        let xml = KSPackager.renderAppxManifest(
            makeInput(deepLink: ["kalsae", "kalsae-dev"]))
        #expect(xml.contains(#"<uap:Protocol Name="kalsae">"#))
        #expect(xml.contains(#"<uap:Protocol Name="kalsae-dev">"#))
    }

    @Test("No protocol extensions when deepLinkSchemes is empty")
    func noDeepLinkExtensionWhenEmpty() {
        let xml = KSPackager.renderAppxManifest(makeInput())
        #expect(xml.contains("uap:Protocol") == false)
    }

    @Test("Startup task extension emitted when ID provided, disabled by default")
    func startupTask() {
        let xml = KSPackager.renderAppxManifest(makeInput(startup: "KalsaeAutostart"))
        #expect(xml.contains(#"Category="windows.startupTask""#))
        #expect(xml.contains(#"TaskId="KalsaeAutostart""#))
        // 사용자가 직접 Settings 에서 켜야 함 (스토어 정책).
        #expect(xml.contains(#"Enabled="false""#))
    }

    @Test("Application Executable uses appName.exe")
    func applicationExecutable() {
        let xml = KSPackager.renderAppxManifest(makeInput())
        #expect(xml.contains(#"Executable="Kalsae Demo.exe""#))
    }

    @Test("XML special characters in display name are escaped")
    func xmlEscaping() {
        let input = KSPackager.MSIXInput(
            appName: "App",
            version: "1.0.0",
            identifier: "dev.kalsae.app",
            publisher: "CN=Acme & Sons",
            displayName: "Tools <Pro>",
            publisherDisplayName: "Acme & Sons",
            description: "5 > 3",
            architecture: .arm64,
            includesWebView2RuntimeDependency: false)
        let xml = KSPackager.renderAppxManifest(input)
        #expect(xml.contains("Tools &lt;Pro&gt;"))
        #expect(xml.contains("Acme &amp; Sons"))
        #expect(xml.contains("5 &gt; 3"))
        #expect(xml.contains(#"ProcessorArchitecture="arm64""#))
    }

    // MARK: - Plan

    @Test("planMSIXPipeline emits MakeAppx pack only when signtool template absent")
    func planMakeAppxOnly() {
        let tmp = FileManager.default.temporaryDirectory
        let plan = KSPackager.planMSIXPipeline(
            .init(
                stagingDir: tmp.appendingPathComponent("staging"),
                outputMSIX: tmp.appendingPathComponent("app.msix"),
                signtoolTemplate: nil))
        #expect(plan.count == 1)
        #expect(plan[0].command == "MakeAppx.exe")
        #expect(plan[0].args.contains("pack"))
        #expect(plan[0].args.contains("/o"))
        #expect(plan[0].args.contains("/d"))
        #expect(plan[0].args.contains("/p"))
    }

    @Test("planMSIXPipeline appends signtool when template provided")
    func planWithSigntool() {
        let tmp = FileManager.default.temporaryDirectory
        let plan = KSPackager.planMSIXPipeline(
            .init(
                stagingDir: tmp,
                outputMSIX: tmp.appendingPathComponent("app.msix"),
                signtoolTemplate: "signtool.exe sign /a /fd sha256"))
        #expect(plan.count == 2)
        #expect(plan[1].label == "signtool")
        #expect(plan[1].viaShell == true)
        #expect(plan[1].command.contains("app.msix"))
    }

    @Test("Signtool template honors {file} placeholder")
    func signtoolPlaceholder() {
        let tmp = FileManager.default.temporaryDirectory
        let out = tmp.appendingPathComponent("out.msix")
        let plan = KSPackager.planMSIXPipeline(
            .init(
                stagingDir: tmp,
                outputMSIX: out,
                signtoolTemplate: #"signtool.exe sign /a /f cert.pfx /p secret {file}"#))
        #expect(plan[1].command.contains("\"\(out.path)\""))
        // Placeholder is substituted, not duplicated at the end.
        #expect(plan[1].command.contains("{file}") == false)
    }
}
