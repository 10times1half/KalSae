import Foundation
import KalsaeCore
import Testing

@testable import KalsaeCLICore

@Suite("ProjectTemplate")
struct ProjectTemplateTests {

    // MARK: - 헬퍼

    private func scaffold(
        name: String = "MyApp",
        frontend: String = "vanilla",
        packageManager: String = "npm"
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kalsae-test-\(UUID().uuidString)")
        try ProjectTemplate(
            name: name,
            frontend: frontend,
            packageManager: packageManager
        ).write(to: tmp)
        return tmp
    }

    // MARK: - 파일 트리

    @Test("Scaffold creates expected files")
    func scaffoldCreatesExpectedFiles() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        let base = root.appendingPathComponent("Sources/MyApp")
        let res = base.appendingPathComponent("Resources")

        #expect(fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path))
        #expect(fm.fileExists(atPath: base.appendingPathComponent("App.swift").path))
        #expect(fm.fileExists(atPath: res.appendingPathComponent("kalsae.json").path))
        #expect(fm.fileExists(atPath: res.appendingPathComponent("index.html").path))
    }

    // MARK: - index.html JS 브리지

    @Test("index.html uses window.__KS_ (not window.__kb)")
    func indexHTMLUsesCorrectGlobal() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let htmlURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/index.html")
        let html = try String(contentsOf: htmlURL, encoding: .utf8)

        #expect(html.contains("window.__KS_"), "Expected window.__KS_ in generated index.html")
        #expect(!html.contains("window.__kb."), "Found legacy window.__kb in generated index.html")
    }

    // MARK: - Kalsae.json

    @Test("Kalsae.json devServerURL defaults to about:blank for vanilla")
    func devServerURLDefault() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(
            json.contains("\"about:blank\""),
            "devServerURL should default to about:blank, got: \(json)")
        #expect(
            !json.contains("localhost:5173"),
            "devServerURL must not point at a dev server by default")
        #expect(
            json.contains("\"devCommand\": null"),
            "vanilla preset should have null devCommand")
        #expect(
            json.contains("\"buildCommand\": null"),
            "vanilla preset should have null buildCommand")
    }

    @Test("Kalsae.json contains commandAllowlist with hello")
    func commandAllowlist() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("commandAllowlist"), "Expected commandAllowlist in Kalsae.json")
        #expect(json.contains("\"hello\""), "Expected hello command in allowlist")
    }

    @Test("Kalsae.json encodes project name and identifier")
    func projectNameEmbedded() throws {
        let root = try scaffold(name: "CoolApp")
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/CoolApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("\"CoolApp\""), "App name missing from Kalsae.json")
        #expect(json.contains("dev.kalsae.coolapp"), "Identifier missing from Kalsae.json")
    }

    @Test("Generated files use shared Kalsae version")
    func generatedFilesUseSharedVersion() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let packageURL = root.appendingPathComponent("Package.swift")

        let json = try String(contentsOf: jsonURL, encoding: .utf8)
        let package = try String(contentsOf: packageURL, encoding: .utf8)

        #expect(
            json.contains("\"version\": \"\(KSVersion.current)\""),
            "generated Kalsae.json should use shared version")
        #expect(
            package.contains("from: \"\(KSVersion.current)\""),
            "generated Package.swift should use shared version")
    }

    // MARK: - 프론트엔드 프리셋

    @Test("React preset writes dist/dev/build fields with specified package manager")
    func reactPresetWithPnpm() throws {
        let root = try scaffold(frontend: "react", packageManager: "pnpm")
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("\"frontendDist\": \"dist\""), "react preset should set frontendDist to dist")
        #expect(json.contains("localhost:5173"), "react preset should set devServerURL")
        #expect(json.contains("\"devCommand\": \"pnpm run dev\""), "react preset should include pnpm dev command")
        #expect(json.contains("\"buildCommand\": \"pnpm run build\""), "react preset should include pnpm build command")
    }

    @Test("Vue preset with yarn uses yarn commands")
    func vuePresetWithYarn() throws {
        let root = try scaffold(frontend: "vue", packageManager: "yarn")
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("\"devCommand\": \"yarn run dev\""), "vue+yarn preset should use yarn dev")
        #expect(json.contains("\"buildCommand\": \"yarn run build\""), "vue+yarn preset should use yarn build")
    }

    @Test("Unknown frontend preset falls back to vanilla defaults")
    func unknownFrontendFallsBackToVanilla() throws {
        let root = try scaffold(frontend: "angular")  // unsupported — fallback
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("\"about:blank\""), "unknown preset should fall back to vanilla")
        #expect(json.contains("\"devCommand\": null"), "unknown preset should have null devCommand")
    }
}
