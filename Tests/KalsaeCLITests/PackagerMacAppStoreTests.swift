import Foundation
import Testing

@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("PackagerMacAppStore (RFC-008 P3)")
struct PackagerMacAppStoreTests {

    private func makeInput(
        installLocation: String = "/Applications"
    ) -> KSPackager.MacAppStoreInput {
        KSPackager.MacAppStoreInput(
            bundle: URL(fileURLWithPath: "/tmp/Demo.app"),
            pkgOutput: URL(fileURLWithPath: "/tmp/Demo-1.0-arm64.pkg"),
            appSigningIdentity: "3rd Party Mac Developer Application: Acme (T1)",
            installerSigningIdentity: "3rd Party Mac Developer Installer: Acme (T1)",
            provisionProfilePath: URL(fileURLWithPath: "/tmp/embedded.provisionprofile"),
            entitlementsPath: URL(fileURLWithPath: "/tmp/Demo.mas.entitlements"),
            installLocation: installLocation)
    }

    @Test("Pipeline produces exactly 3 steps in correct order")
    func threeSteps() {
        let steps = KSPackager.planMacAppStorePipeline(makeInput())
        #expect(steps.count == 3)
        #expect(steps[0].label == "copy-provisioning")
        #expect(steps[1].label == "codesign")
        #expect(steps[2].label == "productbuild")
    }

    @Test("Provisioning step copies into .app/Contents/embedded.provisionprofile")
    func provisioningTarget() {
        let steps = KSPackager.planMacAppStorePipeline(makeInput())
        let cp = steps[0]
        #expect(cp.command == "<cp>")
        #expect(cp.args[0] == "/tmp/embedded.provisionprofile")
        #expect(cp.args[1] == "/tmp/Demo.app/Contents/embedded.provisionprofile")
    }

    @Test("codesign omits --options=runtime (MAS uses sandbox)")
    func codesignNoHardenedRuntime() {
        let steps = KSPackager.planMacAppStorePipeline(makeInput())
        let cs = steps[1]
        #expect(cs.command == "codesign")
        #expect(!cs.args.contains("--options=runtime"))
        #expect(cs.args.contains("--timestamp"))
        #expect(cs.args.contains("--force"))
        #expect(cs.args.contains("--entitlements"))
        #expect(cs.args.contains("/tmp/Demo.mas.entitlements"))
        #expect(cs.args.contains("--sign"))
        #expect(cs.args.contains("3rd Party Mac Developer Application: Acme (T1)"))
        #expect(cs.args.last == "/tmp/Demo.app")
    }

    @Test("productbuild uses installer identity and component install-location")
    func productbuildArgs() {
        let steps = KSPackager.planMacAppStorePipeline(makeInput())
        let pb = steps[2]
        #expect(pb.command == "productbuild")
        #expect(pb.args.contains("--sign"))
        #expect(pb.args.contains("3rd Party Mac Developer Installer: Acme (T1)"))
        #expect(pb.args.contains("--component"))
        #expect(pb.args.contains("/tmp/Demo.app"))
        #expect(pb.args.contains("/Applications"))
        #expect(pb.args.last == "/tmp/Demo-1.0-arm64.pkg")
    }

    @Test("Custom install-location is honored")
    func customInstallLocation() {
        let steps = KSPackager.planMacAppStorePipeline(
            makeInput(installLocation: "/Applications/Utilities"))
        let pb = steps[2]
        #expect(pb.args.contains("/Applications/Utilities"))
    }

    @Test("Execute on non-macOS prints + records skip warning")
    func nonMacOSDryFallback() throws {
        let steps = KSPackager.planMacAppStorePipeline(makeInput())
        var warnings: [String] = []
        try KSPackager.executeMacAppStoreSteps(steps, dryRun: false, warnings: &warnings)
        #if !os(macOS)
            #expect(warnings.contains(where: { $0.contains("non-macOS") }))
        #else
            // macOS 에서는 실제 실행을 시도하므로 본 path 검증은 dry-run 으로.
            warnings.removeAll()
            try KSPackager.executeMacAppStoreSteps(steps, dryRun: true, warnings: &warnings)
            #expect(warnings.isEmpty)
        #endif
    }
}
