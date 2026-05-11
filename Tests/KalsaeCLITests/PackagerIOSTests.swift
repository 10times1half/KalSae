import Testing
import Foundation
@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("PackagerIOS (RFC-008 P4)")
struct PackagerIOSTests {

    private func makeInput(
        method: KSPackager.IOSExportMethod = .appStoreConnect,
        useWorkspace: Bool = false,
        withASCKeys: Bool = false,
        manualSigning: Bool = false
    ) -> KSPackager.IOSPackagingInput {
        let project: KSPackager.IOSProjectKind = useWorkspace
            ? .xcworkspace(URL(fileURLWithPath: "/tmp/Demo.xcworkspace"))
            : .xcodeproj(URL(fileURLWithPath: "/tmp/Demo.xcodeproj"))
        return KSPackager.IOSPackagingInput(
            project: project,
            scheme: "Demo",
            archivePath: URL(fileURLWithPath: "/tmp/build/Demo.xcarchive"),
            exportPath: URL(fileURLWithPath: "/tmp/build/export"),
            exportOptionsPlist: URL(fileURLWithPath: "/tmp/build/ExportOptions.plist"),
            ipaOutput: URL(fileURLWithPath: "/tmp/build/export/Demo.ipa"),
            teamID: "TEAM12345",
            bundleIdentifier: "app.kalsae.demo",
            exportMethod: method,
            appStoreConnectAPIKeyID: withASCKeys ? "KEY123" : nil,
            appStoreConnectAPIIssuerID: withASCKeys ? "ISSUER-UUID" : nil,
            codeSignIdentity: manualSigning ? "Apple Distribution: Acme (TEAM12345)" : nil,
            provisioningProfileSpecifier: manualSigning ? "Demo App Store Profile" : nil)
    }

    // MARK: - Plan

    @Test("Plan w/o ASC keys: 2 steps (archive + exportArchive)")
    func twoStepsWithoutUpload() {
        let steps = KSPackager.planIOSPackagingPipeline(makeInput())
        #expect(steps.count == 2)
        #expect(steps[0].label == "archive")
        #expect(steps[1].label == "exportArchive")
    }

    @Test("Plan w/ ASC keys: 3 steps including altool upload")
    func threeStepsWithUpload() {
        let steps = KSPackager.planIOSPackagingPipeline(makeInput(withASCKeys: true))
        #expect(steps.count == 3)
        #expect(steps[2].label == "upload")
        #expect(steps[2].command == "xcrun")
        #expect(steps[2].args.contains("altool"))
        #expect(steps[2].args.contains("--upload-app"))
        #expect(steps[2].args.contains("--apiKey"))
        #expect(steps[2].args.contains("KEY123"))
        #expect(steps[2].args.contains("--apiIssuer"))
        #expect(steps[2].args.contains("ISSUER-UUID"))
        #expect(steps[2].args.contains("/tmp/build/export/Demo.ipa"))
    }

    @Test("Upload step is omitted for ad-hoc/enterprise even with ASC keys")
    func noUploadForAdHoc() {
        let steps = KSPackager.planIOSPackagingPipeline(
            makeInput(method: .adHoc, withASCKeys: true))
        #expect(steps.count == 2)
        #expect(!steps.contains(where: { $0.label == "upload" }))
    }

    @Test("Archive step uses -project for .xcodeproj")
    func projectArg() {
        let steps = KSPackager.planIOSPackagingPipeline(makeInput(useWorkspace: false))
        let archive = steps[0]
        #expect(archive.command == "xcodebuild")
        #expect(archive.args.contains("-project"))
        #expect(archive.args.contains("/tmp/Demo.xcodeproj"))
        #expect(!archive.args.contains("-workspace"))
    }

    @Test("Archive step uses -workspace for .xcworkspace")
    func workspaceArg() {
        let steps = KSPackager.planIOSPackagingPipeline(makeInput(useWorkspace: true))
        let archive = steps[0]
        #expect(archive.args.contains("-workspace"))
        #expect(archive.args.contains("/tmp/Demo.xcworkspace"))
        #expect(!archive.args.contains("-project"))
    }

    @Test("Archive includes scheme, configuration, destination, and team")
    func archiveCoreArgs() {
        let steps = KSPackager.planIOSPackagingPipeline(makeInput())
        let archive = steps[0]
        #expect(archive.args.contains("-scheme"))
        #expect(archive.args.contains("Demo"))
        #expect(archive.args.contains("-configuration"))
        #expect(archive.args.contains("Release"))
        #expect(archive.args.contains("-destination"))
        #expect(archive.args.contains("generic/platform=iOS"))
        #expect(archive.args.contains("-archivePath"))
        #expect(archive.args.contains("/tmp/build/Demo.xcarchive"))
        #expect(archive.args.contains("archive"))
        #expect(archive.args.contains("DEVELOPMENT_TEAM=TEAM12345"))
        #expect(archive.args.contains("PRODUCT_BUNDLE_IDENTIFIER=app.kalsae.demo"))
    }

    @Test("Automatic signing: no CODE_SIGN_STYLE override in archive")
    func automaticSigningOmitsOverrides() {
        let steps = KSPackager.planIOSPackagingPipeline(makeInput(manualSigning: false))
        let archive = steps[0]
        #expect(!archive.args.contains(where: { $0.hasPrefix("CODE_SIGN_STYLE=") }))
        #expect(!archive.args.contains(where: { $0.hasPrefix("CODE_SIGN_IDENTITY=") }))
    }

    @Test("Manual signing: CODE_SIGN_STYLE=Manual + identity + profile in archive")
    func manualSigningOverrides() {
        let steps = KSPackager.planIOSPackagingPipeline(makeInput(manualSigning: true))
        let archive = steps[0]
        #expect(archive.args.contains("CODE_SIGN_STYLE=Manual"))
        #expect(archive.args.contains(
            "CODE_SIGN_IDENTITY=Apple Distribution: Acme (TEAM12345)"))
        #expect(archive.args.contains(
            "PROVISIONING_PROFILE_SPECIFIER=Demo App Store Profile"))
    }

    @Test("Export step references archive + exportOptionsPlist + exportPath")
    func exportArchiveArgs() {
        let steps = KSPackager.planIOSPackagingPipeline(makeInput())
        let export = steps[1]
        #expect(export.command == "xcodebuild")
        #expect(export.args.contains("-exportArchive"))
        #expect(export.args.contains("-archivePath"))
        #expect(export.args.contains("/tmp/build/Demo.xcarchive"))
        #expect(export.args.contains("-exportOptionsPlist"))
        #expect(export.args.contains("/tmp/build/ExportOptions.plist"))
        #expect(export.args.contains("-exportPath"))
        #expect(export.args.contains("/tmp/build/export"))
    }

    // MARK: - exportOptions.plist 렌더

    @Test("ExportOptions plist contains required keys")
    func exportPlistShape() {
        let xml = KSPackager.renderIOSExportOptionsPlist(
            method: .appStoreConnect,
            teamID: "TEAM12345",
            bundleIdentifier: "app.kalsae.demo")
        #expect(xml.contains("<key>method</key>"))
        #expect(xml.contains("<string>app-store-connect</string>"))
        #expect(xml.contains("<key>teamID</key>"))
        #expect(xml.contains("<string>TEAM12345</string>"))
        #expect(xml.contains("<key>signingStyle</key>"))
        #expect(xml.contains("<string>automatic</string>"))
        #expect(xml.contains("<key>uploadSymbols</key>"))
        #expect(xml.contains("<key>compileBitcode</key>"))
    }

    @Test("ExportOptions manual signing adds provisioningProfiles dict")
    func exportPlistManualProvisioning() {
        let xml = KSPackager.renderIOSExportOptionsPlist(
            method: .appStoreConnect,
            teamID: "TEAM12345",
            bundleIdentifier: "app.kalsae.demo",
            provisioningProfileName: "Demo App Store Profile",
            signingStyle: "manual")
        #expect(xml.contains("<string>manual</string>"))
        #expect(xml.contains("<key>provisioningProfiles</key>"))
        #expect(xml.contains("<key>app.kalsae.demo</key>"))
        #expect(xml.contains("<string>Demo App Store Profile</string>"))
    }

    @Test("ExportOptions automatic signing omits provisioningProfiles dict")
    func exportPlistAutomaticNoProfiles() {
        let xml = KSPackager.renderIOSExportOptionsPlist(
            method: .appStoreConnect,
            teamID: "TEAM12345",
            bundleIdentifier: "app.kalsae.demo",
            provisioningProfileName: "Should Be Ignored",
            signingStyle: "automatic")
        #expect(!xml.contains("<key>provisioningProfiles</key>"))
    }

    // MARK: - Usage descriptions

    @Test("renderIOSUsageDescriptions emits only enabled permissions")
    func usageDescriptionsGate() {
        let perms = KSPermissionsConfig(
            camera: .granted(reason: "Scan QR"),
            microphone: .denied,
            photoLibrary: .granted())
        let xml = KSPackager.renderIOSUsageDescriptions(perms)
        #expect(xml.contains("<key>NSCameraUsageDescription</key>"))
        #expect(xml.contains("<string>Scan QR</string>"))
        #expect(xml.contains("<key>NSPhotoLibraryUsageDescription</key>"))
        // 기본 reason 채워야 함
        #expect(xml.contains("photo library"))
        #expect(!xml.contains("NSMicrophoneUsageDescription"))
        #expect(!xml.contains("NSLocationWhenInUseUsageDescription"))
    }

    @Test("Usage description XML-escapes special chars in reason")
    func usageDescriptionEscape() {
        let perms = KSPermissionsConfig(
            camera: .granted(reason: "Scan <code>QR</code> & docs"))
        let xml = KSPackager.renderIOSUsageDescriptions(perms)
        #expect(xml.contains("&lt;code&gt;"))
        #expect(xml.contains("&amp;"))
    }

    // MARK: - Executor

    @Test("Execute on non-macOS prints + records skip warning")
    func nonMacOSDryFallback() throws {
        let steps = KSPackager.planIOSPackagingPipeline(makeInput())
        var warnings: [String] = []
        try KSPackager.executeIOSSteps(steps, dryRun: false, warnings: &warnings)
        #if !os(macOS)
            #expect(warnings.contains(where: { $0.contains("non-macOS") }))
        #else
            warnings.removeAll()
            try KSPackager.executeIOSSteps(steps, dryRun: true, warnings: &warnings)
            #expect(warnings.isEmpty)
        #endif
    }
}
