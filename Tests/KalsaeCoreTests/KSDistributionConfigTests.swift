import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSDistributionConfig / Permissions (RFC-008)")
struct KSDistributionConfigTests {

    // MARK: - KSDistributionTarget

    @Test("parse() accepts short and long aliases")
    func parseAliases() {
        #expect(KSDistributionTarget.parse("dev") == .developer)
        #expect(KSDistributionTarget.parse("developer") == .developer)
        #expect(KSDistributionTarget.parse("devid") == .developerID)
        #expect(KSDistributionTarget.parse("developer-id") == .developerID)
        #expect(KSDistributionTarget.parse("mas") == .macAppStore)
        #expect(KSDistributionTarget.parse("mac-app-store") == .macAppStore)
        #expect(KSDistributionTarget.parse("win-store") == .microsoftStore)
        #expect(KSDistributionTarget.parse("microsoft-store") == .microsoftStore)
        #expect(KSDistributionTarget.parse("ios-appstore") == .iosAppStore)
        #expect(KSDistributionTarget.parse("ios-app-store") == .iosAppStore)
        #expect(KSDistributionTarget.parse("nonsense") == nil)
    }

    @Test("shortName round-trips through parse()")
    func shortNameRoundTrip() {
        for t in [
            KSDistributionTarget.developer,
            .developerID,
            .macAppStore,
            .microsoftStore,
            .iosAppStore,
        ] {
            #expect(KSDistributionTarget.parse(t.shortName) == t)
        }
    }

    @Test("requiresAppSandbox / prefersManifestRegistration are correct")
    func capabilityFlags() {
        #expect(KSDistributionTarget.developer.requiresAppSandbox == false)
        #expect(KSDistributionTarget.developerID.requiresAppSandbox == false)
        #expect(KSDistributionTarget.macAppStore.requiresAppSandbox == true)
        #expect(KSDistributionTarget.microsoftStore.requiresAppSandbox == false)
        #expect(KSDistributionTarget.iosAppStore.requiresAppSandbox == true)

        #expect(KSDistributionTarget.macAppStore.prefersManifestRegistration == true)
        #expect(KSDistributionTarget.microsoftStore.prefersManifestRegistration == true)
        #expect(KSDistributionTarget.developer.prefersManifestRegistration == false)
    }

    // MARK: - KSDistributionConfig decoding

    @Test("Distribution config decodes target via parse() with friendly aliases")
    func decodeTargetAliases() throws {
        let json = #"""
            { "target": "mas", "appleTeamID": "ABCDE12345" }
            """#
        let cfg = try JSONDecoder().decode(
            KSDistributionConfig.self, from: Data(json.utf8))
        #expect(cfg.target == .macAppStore)
        #expect(cfg.appleTeamID == "ABCDE12345")
    }

    @Test("Distribution config rejects unknown target with a clear error")
    func decodeUnknownTarget() {
        let json = #"""
            { "target": "play-store" }
            """#
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                KSDistributionConfig.self, from: Data(json.utf8))
        }
    }

    // MARK: - KSPermissionEntry decoding

    @Test("Permission entry decodes from bare bool")
    func permissionBareBool() throws {
        let json = #"""
            { "camera": true, "microphone": false }
            """#
        let perms = try JSONDecoder().decode(
            KSPermissionsConfig.self, from: Data(json.utf8))
        #expect(perms.camera.enabled == true)
        #expect(perms.microphone.enabled == false)
    }

    @Test("Permission entry decodes from object with reason")
    func permissionObject() throws {
        let json = #"""
            {
              "camera": { "enabled": true, "reason": "Demo capture" },
              "location": { "enabled": false }
            }
            """#
        let perms = try JSONDecoder().decode(
            KSPermissionsConfig.self, from: Data(json.utf8))
        #expect(perms.camera.enabled == true)
        #expect(perms.camera.reason == "Demo capture")
        #expect(perms.location.enabled == false)
        #expect(perms.location.reason == nil)
    }

    // MARK: - KSConfig integration

    @Test("KSConfig defaults distribution=.developer and permissions=.denied")
    func kSConfigDefaults() throws {
        let json = #"""
            {
              "app": {
                "name": "Demo",
                "version": "0.1.0",
                "identifier": "dev.kalsae.demo"
              },
              "build": {
                "frontendDist": "dist",
                "devServerURL": "http://localhost:5173"
              },
              "windows": [
                { "label": "main", "title": "Demo", "width": 800, "height": 600 }
              ],
              "security": { "csp": "default-src 'self'" }
            }
            """#
        let cfg = try JSONDecoder().decode(KSConfig.self, from: Data(json.utf8))
        #expect(cfg.distribution.target == .developer)
        #expect(cfg.permissions.camera.enabled == false)
        #expect(cfg.permissions.microphone.enabled == false)
    }
}
