import Testing
import Foundation
@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("EntitlementsGenerator (RFC-008 P3)")
struct EntitlementsGeneratorTests {

    /// Test fixture with the required `build` + `windows` fields.
    private func makeConfig() -> KSConfig {
        KSConfig(
            app: KSAppInfo(
                name: "Demo", version: "0.1.0", identifier: "app.kalsae.demo"),
            build: KSBuildConfig(frontendDist: "dist"),
            windows: [KSWindowConfig(
                label: "main", title: "Demo", width: 800, height: 600)])
    }

    // MARK: - 기본 매핑

    @Test("Developer ID: cs.allow-jit only, no sandbox, no app-id")
    func developerIDMinimal() {
        let input = EntitlementsInput(target: .developerID)
        let xml = renderEntitlementsPlist(input)
        #expect(xml.contains("<key>com.apple.security.cs.allow-jit</key>"))
        #expect(!xml.contains("app-sandbox"))
        #expect(!xml.contains("application-identifier"))
        #expect(!xml.contains("team-identifier"))
        #expect(!xml.contains("network.client"))
    }

    @Test("MAS: cs.allow-jit + app-sandbox + app-id + team-id + files.user-selected")
    func macAppStoreBaseline() {
        let input = EntitlementsInput(
            target: .macAppStore,
            applicationIdentifier: "ABCDE12345.app.kalsae.demo",
            teamIdentifier: "ABCDE12345")
        let xml = renderEntitlementsPlist(input)
        #expect(xml.contains("<key>com.apple.security.cs.allow-jit</key>"))
        #expect(xml.contains("<key>com.apple.security.app-sandbox</key>"))
        #expect(xml.contains("<key>application-identifier</key>"))
        #expect(xml.contains("<string>ABCDE12345.app.kalsae.demo</string>"))
        #expect(xml.contains("<key>com.apple.developer.team-identifier</key>"))
        #expect(xml.contains("<string>ABCDE12345</string>"))
        #expect(xml.contains(
            "<key>com.apple.security.files.user-selected.read-write</key>"))
    }

    @Test("network.client appears only when allowOutboundHTTP=true")
    func networkClientToggle() {
        let off = renderEntitlementsPlist(
            EntitlementsInput(target: .macAppStore, allowOutboundHTTP: false))
        let on = renderEntitlementsPlist(
            EntitlementsInput(target: .macAppStore, allowOutboundHTTP: true))
        #expect(!off.contains("network.client"))
        #expect(on.contains("<key>com.apple.security.network.client</key>"))
    }

    @Test("network.server appears only when allowIncomingNetwork=true")
    func networkServerToggle() {
        let on = renderEntitlementsPlist(
            EntitlementsInput(target: .macAppStore, allowIncomingNetwork: true))
        #expect(on.contains("<key>com.apple.security.network.server</key>"))
    }

    @Test("camera/microphone/photoLibrary/location entitlements gate properly")
    func devicePermissions() {
        let all = renderEntitlementsPlist(EntitlementsInput(
            target: .macAppStore,
            requiresCamera: true,
            requiresMicrophone: true,
            requiresPhotoLibrary: true,
            requiresLocation: true))
        #expect(all.contains("<key>com.apple.security.device.camera</key>"))
        #expect(all.contains("<key>com.apple.security.device.audio-input</key>"))
        #expect(all.contains(
            "<key>com.apple.security.personal-information.photos-library</key>"))
        #expect(all.contains(
            "<key>com.apple.security.personal-information.location</key>"))

        let none = renderEntitlementsPlist(
            EntitlementsInput(target: .macAppStore))
        #expect(!none.contains("device.camera"))
        #expect(!none.contains("audio-input"))
        #expect(!none.contains("photos-library"))
        #expect(!none.contains("personal-information.location"))
    }

    @Test("Developer ID does not emit files.user-selected even when usesFileDialogs=true")
    func developerIDNoUserSelected() {
        let xml = renderEntitlementsPlist(EntitlementsInput(
            target: .developerID, usesFileDialogs: true))
        #expect(!xml.contains("files.user-selected"))
    }

    // MARK: - makeEntitlementsInput config 매핑

    @Test("makeEntitlementsInput derives application-identifier from team+bundle")
    func deriveApplicationIdentifier() {
        var config = makeConfig()
        config.distribution = KSDistributionConfig(
            target: .macAppStore, appleTeamID: "TEAM123XYZ")
        let input = makeEntitlementsInput(config: config, target: .macAppStore)
        #expect(input.applicationIdentifier == "TEAM123XYZ.app.kalsae.demo")
        #expect(input.teamIdentifier == "TEAM123XYZ")
    }

    @Test("makeEntitlementsInput honors explicit applicationIdentifier override")
    func explicitApplicationIdentifier() {
        var config = makeConfig()
        config.distribution = KSDistributionConfig(
            target: .macAppStore, appleTeamID: "TEAM123XYZ")
        let input = makeEntitlementsInput(
            config: config, target: .macAppStore,
            applicationIdentifier: "OVERRIDE.app.kalsae.demo")
        #expect(input.applicationIdentifier == "OVERRIDE.app.kalsae.demo")
    }

    @Test("makeEntitlementsInput derives allowOutboundHTTP from security.http.allow")
    func deriveOutboundHTTP() {
        var config = makeConfig()
        config.security.http.allow = ["https://api.example.com"]
        let input = makeEntitlementsInput(config: config, target: .macAppStore)
        #expect(input.allowOutboundHTTP == true)
    }

    @Test("makeEntitlementsInput maps permissions.camera/microphone/etc")
    func derivePermissions() {
        var config = makeConfig()
        config.permissions = KSPermissionsConfig(
            camera: .granted(reason: "Scan QR"),
            microphone: .granted(),
            networkServer: true)
        let input = makeEntitlementsInput(config: config, target: .macAppStore)
        #expect(input.requiresCamera == true)
        #expect(input.requiresMicrophone == true)
        #expect(input.allowIncomingNetwork == true)
        #expect(input.requiresPhotoLibrary == false)
        #expect(input.requiresLocation == false)
    }

    @Test("Developer ID target produces nil application-identifier even with team")
    func developerIDNoAppID() {
        var config = makeConfig()
        config.distribution = KSDistributionConfig(
            target: .developerID, appleTeamID: "TEAM123XYZ")
        let input = makeEntitlementsInput(config: config, target: .developerID)
        #expect(input.applicationIdentifier == nil)
    }

    @Test("Rendered plist is well-formed XML with plist DOCTYPE")
    func plistDoctype() {
        let xml = renderEntitlementsPlist(
            EntitlementsInput(target: .macAppStore))
        #expect(xml.hasPrefix("<?xml version=\"1.0\""))
        #expect(xml.contains("<!DOCTYPE plist PUBLIC"))
        #expect(xml.contains("<plist version=\"1.0\">"))
        #expect(xml.hasSuffix("</plist>\n"))
    }
}
