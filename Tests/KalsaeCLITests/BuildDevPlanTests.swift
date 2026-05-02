import Testing
import Foundation
@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("KSBuildPlan")
struct BuildPlanTests {
    private func makeConfig(devServerURL: String = "about:blank",
                            devCommand: String? = nil,
                            buildCommand: String? = nil) -> KSConfig {
        KSConfig(
            app: KSAppInfo(name: "Demo", version: "0.1.0", identifier: "dev.kalsae.demo"),
            build: KSBuildConfig(
                frontendDist: "dist",
                devServerURL: devServerURL,
                devCommand: devCommand,
                buildCommand: buildCommand),
            windows: [KSWindowConfig(label: "main", title: "Demo", width: 800, height: 600)])
    }

    @Test("swift build arguments include debug and target")
    func buildArgs() {
        let args = KSBuildPlan.swiftBuildArguments(debug: true, target: "demo-app")
        #expect(args == ["build", "-c", "debug", "--target", "demo-app"])
    }

    @Test("build command normalization trims whitespace")
    func normalizeBuildCommand() {
        #expect(KSBuildPlan.normalizedCommand("  npm run build  ") == "npm run build")
        #expect(KSBuildPlan.normalizedCommand("   ") == nil)
    }

    @Test("dist resolution prefers override path")
    func distResolutionOverride() {
        let config = makeConfig()
        let cwd = URL(fileURLWithPath: "C:/repo")
        let configURL = URL(fileURLWithPath: "C:/repo/Sources/App/Resources/Kalsae.json")
        let dist = KSBuildPlan.resolveDistURL(
            config: config,
            configURL: configURL,
            cwd: cwd,
            distOverride: "frontend/out")
        #expect(dist.path.replacingOccurrences(of: "\\", with: "/").hasSuffix("/frontend/out"))
    }

    @Test("dist validation fails when missing")
    func distValidationMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-dist-missing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            try KSBuildPlan.validateFrontendDist(
                at: root.appendingPathComponent("dist"),
                allowMissingDist: false)
            Issue.record("Expected missing dist validation to fail.")
        } catch let error as KSBuildPlanError {
            #expect(error.description.contains("not found"))
        }
    }

    @Test("allowMissingDist bypasses dist validation")
    func distValidationBypass() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-dist-bypass-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try KSBuildPlan.validateFrontendDist(
            at: root.appendingPathComponent("dist"),
            allowMissingDist: true)
    }
}

@Suite("KSDevPlan")
struct DevPlanTests {
    private func makeConfig(devServerURL: String = "about:blank",
                            devCommand: String? = nil) -> KSConfig {
        KSConfig(
            app: KSAppInfo(name: "Demo", version: "0.1.0", identifier: "dev.kalsae.demo"),
            build: KSBuildConfig(
                frontendDist: "dist",
                devServerURL: devServerURL,
                devCommand: devCommand,
                buildCommand: nil),
            windows: [KSWindowConfig(label: "main", title: "Demo", width: 800, height: 600)])
    }

    @Test("skipDevCommand removes configured command")
    func skipDevCommand() {
        let config = makeConfig(devServerURL: "http://localhost:5173", devCommand: "npm run dev")
        let plan = KSDevPlan.make(config: config, skipDevCommand: true, noWaitDevServer: false)
        #expect(plan.devCommand == nil)
        #expect(plan.shouldWaitForDevServer)
    }

    @Test("noWaitDevServer disables readiness wait")
    func noWaitDevServer() {
        let config = makeConfig(devServerURL: "http://localhost:5173", devCommand: "npm run dev")
        let plan = KSDevPlan.make(config: config, skipDevCommand: false, noWaitDevServer: true)
        #expect(plan.devCommand == "npm run dev")
        #expect(!plan.shouldWaitForDevServer)
    }

    @Test("non-http devServerURL does not trigger wait")
    func nonRemoteDevServer() {
        let config = makeConfig(devServerURL: "about:blank", devCommand: "npm run dev")
        let plan = KSDevPlan.make(config: config, skipDevCommand: false, noWaitDevServer: false)
        #expect(plan.devCommand == "npm run dev")
        #expect(!plan.shouldWaitForDevServer)
    }

    @Test("dev command normalization trims whitespace")
    func normalizeDevCommand() {
        let config = makeConfig(devServerURL: "http://localhost:5173", devCommand: "  npm run dev  ")
        let plan = KSDevPlan.make(config: config, skipDevCommand: false, noWaitDevServer: false)
        #expect(plan.devCommand == "npm run dev")
        #expect(plan.shouldWaitForDevServer)
    }
}
