import Foundation
import Testing

@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("KSBuildPlan")
struct BuildPlanTests {
    private func makeConfig(
        devServerURL: String = "about:blank",
        devCommand: String? = nil,
        buildCommand: String? = nil
    ) -> KSConfig {
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

    @Test("swift build arguments forward --jobs as -j N when provided")
    func buildArgsWithJobs() {
        let args = KSBuildPlan.swiftBuildArguments(
            debug: false, target: nil, jobs: 4)
        #expect(args == ["build", "-c", "release", "-j", "4"])
    }

    @Test("swift build arguments omit -j when jobs is nil")
    func buildArgsWithoutJobs() {
        let args = KSBuildPlan.swiftBuildArguments(
            debug: false, target: nil, jobs: nil)
        #expect(args == ["build", "-c", "release"])
        #expect(!args.contains("-j"))
    }

    @Test("swift build arguments place -j after --target")
    func buildArgsJobsAfterTarget() {
        let args = KSBuildPlan.swiftBuildArguments(
            debug: true, target: "demo-app", jobs: 2)
        #expect(args == ["build", "-c", "debug", "--target", "demo-app", "-j", "2"])
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

    @Test("dist validation fails when index.html is missing")
    func distValidationMissingIndex() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("kalsae-dist-noindex-\(UUID().uuidString)")
        let dist = root.appendingPathComponent("dist")
        try fm.createDirectory(at: dist, withIntermediateDirectories: true)
        // 산출물은 있지만 index.html 이 없는 상태를 흉내낸다.
        try Data("console.log(0)".utf8).write(
            to: dist.appendingPathComponent("app.js"))
        defer { try? fm.removeItem(at: root) }

        do {
            try KSBuildPlan.validateFrontendDist(
                at: dist, allowMissingDist: false)
            Issue.record("Expected missing index.html to fail validation.")
        } catch let error as KSBuildPlanError {
            #expect(error.description.contains("index.html"))
        }
    }

    @Test("dist validation passes when index.html present")
    func distValidationWithIndex() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("kalsae-dist-ok-\(UUID().uuidString)")
        let dist = root.appendingPathComponent("dist")
        try fm.createDirectory(at: dist, withIntermediateDirectories: true)
        try Data("<html></html>".utf8).write(
            to: dist.appendingPathComponent("index.html"))
        defer { try? fm.removeItem(at: root) }

        try KSBuildPlan.validateFrontendDist(
            at: dist, allowMissingDist: false)
    }
}
@Suite("KSDevPlan")
struct DevPlanTests {
    private func makeConfig(
        devServerURL: String = "about:blank",
        devCommand: String? = nil
    ) -> KSConfig {
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

    @Test("--frontend-dev-server-url overrides config")
    func devServerURLOverride() {
        let config = makeConfig(devServerURL: "http://localhost:5173")
        let plan = KSDevPlan.make(
            config: config,
            skipDevCommand: false,
            noWaitDevServer: false,
            devServerURLOverride: "http://localhost:9000")
        #expect(plan.devServerURL == "http://localhost:9000")
        #expect(plan.shouldWaitForDevServer)
    }

    @Test("blank --frontend-dev-server-url falls back to config")
    func devServerURLOverrideBlank() {
        let config = makeConfig(devServerURL: "http://localhost:5173")
        let plan = KSDevPlan.make(
            config: config,
            skipDevCommand: false,
            noWaitDevServer: false,
            devServerURLOverride: "   ")
        #expect(plan.devServerURL == "http://localhost:5173")
    }
}
