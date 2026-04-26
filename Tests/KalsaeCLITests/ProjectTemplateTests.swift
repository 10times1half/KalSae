import Testing
import Foundation
@testable import KalsaeCLICore

@Suite("ProjectTemplate")
struct ProjectTemplateTests {

    // MARK: - Helpers

    private func scaffold(name: String = "MyApp") throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kalsae-test-\(UUID().uuidString)")
        try ProjectTemplate(name: name).write(to: tmp)
        return tmp
    }

    // MARK: - File tree

    @Test("Scaffold creates expected files")
    func scaffoldCreatesExpectedFiles() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        let base = root.appendingPathComponent("Sources/MyApp")
        let res  = base.appendingPathComponent("Resources")

        #expect(fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path))
        #expect(fm.fileExists(atPath: base.appendingPathComponent("App.swift").path))
        #expect(fm.fileExists(atPath: res.appendingPathComponent("kalsae.json").path))
        #expect(fm.fileExists(atPath: res.appendingPathComponent("index.html").path))
    }

    // MARK: - index.html JS bridge

    @Test("index.html uses window.__KS_ (not window.__kb)")
    func indexHTMLUsesCorrectGlobal() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let htmlURL = root
            .appendingPathComponent("Sources/MyApp/Resources/index.html")
        let html = try String(contentsOf: htmlURL, encoding: .utf8)

        #expect(html.contains("window.__KS_"),  "Expected window.__KS_ in generated index.html")
        #expect(!html.contains("window.__kb."), "Found legacy window.__kb in generated index.html")
    }

    // MARK: - Kalsae.json

    @Test("Kalsae.json devServerURL defaults to about:blank")
    func devServerURLDefault() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL = root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("\"about:blank\""),
                "devServerURL should default to about:blank, got: \(json)")
        #expect(!json.contains("localhost:5173"),
                "devServerURL must not point at a dev server by default")
    }

    @Test("Kalsae.json contains commandAllowlist with hello")
    func commandAllowlist() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL = root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("commandAllowlist"), "Expected commandAllowlist in Kalsae.json")
        #expect(json.contains("\"hello\""),        "Expected hello command in allowlist")
    }

    @Test("Kalsae.json encodes project name and identifier")
    func projectNameEmbedded() throws {
        let root = try scaffold(name: "CoolApp")
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL = root
            .appendingPathComponent("Sources/CoolApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("\"CoolApp\""),             "App name missing from Kalsae.json")
        #expect(json.contains("dev.kalsae.coolapp"),   "Identifier missing from Kalsae.json")
    }
}
