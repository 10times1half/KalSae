import Testing
import Foundation
@testable import KalsaeCLICore

@Suite("KSDoctor")
struct DoctorTests {
    private func makeTempProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-doctor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    @Test("Reports missing config")
    func missingConfig() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = KSDoctor.run(.init(projectRoot: root))
        #expect(report.warnings.contains { $0.contains("Config file not found") })
    }

    @Test("Accepts valid config and non-empty dist")
    func validConfigAndDist() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("Kalsae.json")
        let distURL = root.appendingPathComponent("dist")
        try FileManager.default.createDirectory(at: distURL, withIntermediateDirectories: true)
        try write("<html></html>", to: distURL.appendingPathComponent("index.html"))

        try write(
            #"{"app":{"name":"Demo","version":"0.1.0","identifier":"dev.kalsae.demo"},"build":{"frontendDist":"dist","devServerURL":"about:blank"},"windows":[{"label":"main","title":"Demo","width":800,"height":600}]}"#,
            to: configURL)

        #if os(Windows)
        let webView2 = root
            .appendingPathComponent("Vendor")
            .appendingPathComponent("WebView2")
            .appendingPathComponent("build")
            .appendingPathComponent("native")
            .appendingPathComponent("x64")
        try FileManager.default.createDirectory(at: webView2, withIntermediateDirectories: true)
        try write("stub", to: webView2.appendingPathComponent("WebView2LoaderStatic.lib"))
        #endif

        let report = KSDoctor.run(.init(projectRoot: root))

        #expect(report.warnings.isEmpty)
        #expect(report.infos.contains { $0.contains("Loaded config") })
        #expect(report.infos.contains { $0.contains("Frontend dist is ready") })
    }

    @Test("Warns when swift-syntax cache remote is invalid")
    func invalidSwiftSyntaxRemote() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let cache = root
            .appendingPathComponent(".build")
            .appendingPathComponent("repositories")
            .appendingPathComponent("swift-syntax-test")
            .appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try write("[remote \"origin\"]\nurl = https://example.invalid/swift-syntax.git\n",
                  to: cache.appendingPathComponent("config"))

        let report = KSDoctor.run(.init(projectRoot: root))
        #expect(report.warnings.contains { $0.contains("swift-syntax cache remote looks invalid") })
    }
}
