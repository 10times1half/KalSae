import Foundation
import Testing

@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("KSPackager Developer ID signing plan (RFC-008 P1)")
struct PackagerMacSigningTests {

    private func makeInput(
        notary: String? = "kalsae-notary",
        entitlements: URL? = nil,
        target: KSDistributionTarget = .developerID
    ) -> KSPackager.MacSignInput {
        let tmp = FileManager.default.temporaryDirectory
        return KSPackager.MacSignInput(
            bundle: tmp.appendingPathComponent("Demo.app"),
            zipOutput: tmp.appendingPathComponent("Demo-1.0-notarize.zip"),
            identity: "Developer ID Application: Acme Inc (TEAM12345)",
            notarytoolProfile: notary,
            entitlementsPath: entitlements,
            defaultEntitlementsPath: tmp.appendingPathComponent("Demo.entitlements"),
            target: target)
    }

    @Test("plan with profile = 4 steps in order: codesign / ditto / notarize / staple")
    func planFullPipeline() {
        let steps = KSPackager.planDeveloperIDSigning(makeInput())
        #expect(steps.count == 4)
        #expect(steps[0].label == "codesign")
        #expect(steps[0].command == "codesign")
        #expect(steps[1].label == "ditto")
        #expect(steps[1].command == "ditto")
        #expect(steps[2].label == "notarize")
        #expect(steps[2].command == "xcrun")
        #expect(steps[2].args.first == "notarytool")
        #expect(steps[2].args.contains("submit"))
        #expect(steps[2].args.contains("--keychain-profile"))
        #expect(steps[2].args.contains("kalsae-notary"))
        #expect(steps[2].args.contains("--wait"))
        #expect(steps[3].label == "staple")
        #expect(steps[3].args == ["stapler", "staple", steps[0].args.last!])
    }

    @Test("plan without notary profile = codesign + ditto only")
    func planWithoutNotary() {
        let steps = KSPackager.planDeveloperIDSigning(makeInput(notary: nil))
        #expect(steps.count == 2)
        #expect(steps[0].label == "codesign")
        #expect(steps[1].label == "ditto")
    }

    @Test("codesign step injects --options=runtime and --timestamp for Developer ID")
    func codesignHardenedFlags() {
        let steps = KSPackager.planDeveloperIDSigning(makeInput())
        let cs = steps[0]
        #expect(cs.args.contains("--force"))
        #expect(cs.args.contains("--options=runtime"))
        #expect(cs.args.contains("--timestamp"))
        #expect(cs.args.contains("--sign"))
        #expect(cs.args.contains("Developer ID Application: Acme Inc (TEAM12345)"))
    }

    @Test("codesign uses provided entitlements path when supplied")
    func codesignCustomEntitlements() {
        let tmp = FileManager.default.temporaryDirectory
        let custom = tmp.appendingPathComponent("custom.entitlements")
        let steps = KSPackager.planDeveloperIDSigning(makeInput(entitlements: custom))
        let cs = steps[0]
        #expect(cs.args.contains("--entitlements"))
        #expect(cs.args.contains(custom.path))
    }

    @Test("codesign falls back to defaultEntitlementsPath when none supplied")
    func codesignDefaultEntitlements() {
        let input = makeInput(entitlements: nil)
        let steps = KSPackager.planDeveloperIDSigning(input)
        let cs = steps[0]
        #expect(cs.args.contains(input.defaultEntitlementsPath.path))
    }

    @Test("ditto uses --keepParent so the .app survives inside the zip")
    func dittoKeepParent() {
        let steps = KSPackager.planDeveloperIDSigning(makeInput())
        let ditto = steps[1]
        #expect(ditto.args.contains("-c"))
        #expect(ditto.args.contains("-k"))
        #expect(ditto.args.contains("--keepParent"))
    }

    @Test("MAS target omits --options=runtime (sandbox path, not hardened runtime)")
    func masOmitsHardenedRuntime() {
        let steps = KSPackager.planDeveloperIDSigning(
            makeInput(target: .macAppStore))
        #expect(steps[0].args.contains("--options=runtime") == false)
    }

    @Test("Default Hardened Runtime entitlements enable JIT only")
    func defaultEntitlementsXML() {
        let xml = KSPackager.renderDefaultHardenedRuntimeEntitlements()
        #expect(xml.contains("com.apple.security.cs.allow-jit"))
        #expect(xml.contains("<true/>"))
        // sandbox는 켜지 않는다 (MAS 와 구분).
        #expect(xml.contains("com.apple.security.app-sandbox") == false)
    }
}
