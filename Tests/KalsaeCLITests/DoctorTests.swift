import Foundation
import Testing

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

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        #expect(report.warnings.contains { $0.contains("Config file not found") })
    }

    @Test("Accepts valid config")
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
            let webView2Include =
                root
                .appendingPathComponent("Vendor")
                .appendingPathComponent("WebView2")
                .appendingPathComponent("build")
                .appendingPathComponent("native")
                .appendingPathComponent("include")
            try FileManager.default.createDirectory(at: webView2Include, withIntermediateDirectories: true)
            try write("stub", to: webView2Include.appendingPathComponent("WebView2.h"))
        #endif

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))

        #expect(report.warnings.isEmpty)
        #expect(report.infos.contains { $0.contains("Loaded config") })
        // doctor는 더 이상 frontendDist를 검증하지 않는다.
        #expect(!report.infos.contains { $0.contains("Frontend dist") })
    }

    @Test("Reports warning for invalid JSON config")
    func invalidJSONConfig() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let configURL = root.appendingPathComponent("Kalsae.json")
        try write("not valid json", to: configURL)

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        #expect(
            report.warnings.contains {
                $0.contains("Config") || $0.contains("config") || $0.contains("parse") || $0.contains("invalid")
            })
    }

    @Test("Warns when swift-syntax cache remote is invalid")
    func invalidSwiftSyntaxRemote() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let cache =
            root
            .appendingPathComponent(".build")
            .appendingPathComponent("repositories")
            .appendingPathComponent("swift-syntax-test")
            .appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try write(
            "[remote \"origin\"]\nurl = https://example.invalid/swift-syntax.git\n",
            to: cache.appendingPathComponent("config"))

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        #expect(report.warnings.contains { $0.contains("swift-syntax cache remote looks invalid") })
    }

    @Test("skipExternalChecks suppresses Node/npm probes")
    func skipsExternalChecks() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        // package.json이 있어도 skipExternalChecks=true이면 node/npm 메시지가 등장하지 않아야 한다.
        try write("{}", to: root.appendingPathComponent("package.json"))

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))

        #expect(report.nodeVersion == nil)
        #expect(report.npmVersion == nil)
        #expect(!report.infos.contains { $0.contains("Node.js") })
        #expect(!report.warnings.contains { $0.contains("Node.js") })
    }

    @Test("Vanilla project (no package.json) reports missing node as info, not warning")
    func vanillaProjectNoNode() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: false))

        if findExecutable(named: "node") == nil {
            // package.json 없음 → warning이 아니라 info로 보고되어야 한다.
            #expect(
                report.infos.contains {
                    $0.contains("Node.js not found") && $0.contains("non-vanilla")
                })
            #expect(!report.warnings.contains { $0.contains("Node.js not found") })
        } else {
            #expect(report.nodeVersion != nil)
        }
    }

    @Test("Captures host environment metadata")
    func capturesHostEnvironment() throws {
        let root = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = KSDoctor.run(.init(projectRoot: root, skipExternalChecks: true))
        // OS / arch / version 은 외부 프로세스 없이도 항상 채워진다.
        #expect(report.osName != nil)
        #expect(report.osVersion != nil)
        #expect(report.architecture != nil)
        // skipExternalChecks=true 인 경우 swift --version 호출은 건너뛴다.
        #expect(report.swiftVersion == nil)
    }
}
