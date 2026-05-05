import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSNSISTemplate / KSPackager.runNSIS")
struct PackagerNSISTests {

    private func uniqueDir(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-nsis-\(UUID().uuidString)-\(suffix)")
    }

    private func makeSourceTree(at root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "x".write(
            to: root.appendingPathComponent("Demo.exe"),
            atomically: false, encoding: .utf8)
        try "{}".write(
            to: root.appendingPathComponent("Kalsae.json"),
            atomically: false, encoding: .utf8)
        try fm.createDirectory(
            at: root.appendingPathComponent("Resources"),
            withIntermediateDirectories: true)
        try "<html></html>".write(
            to: root.appendingPathComponent("Resources/index.html"),
            atomically: false, encoding: .utf8)
    }

    @Test("Renders required NSIS sections and tokens")
    func rendersRequiredSections() {
        let opts = KSNSISTemplate.Options(
            appName: "Demo",
            version: "1.2.3",
            identifier: "dev.kalsae.demo",
            publisher: "Acme Inc.",
            architecture: .x64,
            sourceDir: URL(fileURLWithPath: "C:/tmp/Demo"),
            iconPath: nil,
            webView2BootstrapperFileName: nil)

        let body = KSNSISTemplate.render(opts)
        #expect(body.contains("!define APP_NAME \"Demo\""))
        #expect(body.contains("Name \"${APP_NAME}\""))
        #expect(body.contains("!define APP_VERSION \"1.2.3\""))
        #expect(body.contains("!define APP_IDENTIFIER \"dev.kalsae.demo\""))
        #expect(body.contains("!define APP_PUBLISHER \"Acme Inc.\""))
        #expect(body.contains("Section \"Install\""))
        #expect(body.contains("Section \"Uninstall\""))
        #expect(body.contains("WriteUninstaller"))
        #expect(body.contains("CreateShortcut \"$DESKTOP\\${APP_NAME}.lnk\""))
        #expect(body.contains("InstallLocation"))
    }

    @Test("Includes WebView2 bootstrap section when bootstrapper supplied")
    func bootstrapperSection() {
        let opts = KSNSISTemplate.Options(
            appName: "Demo",
            version: "0.1.0",
            identifier: "dev.kalsae.demo",
            architecture: .x64,
            sourceDir: URL(fileURLWithPath: "C:/tmp/Demo"),
            webView2BootstrapperFileName: "MicrosoftEdgeWebview2Setup.exe")
        let body = KSNSISTemplate.render(opts)
        #expect(body.contains("/silent /install"))
        #expect(body.contains("/x \"MicrosoftEdgeWebview2Setup.exe\""))
    }

    @Test("Excludes WebView2 bootstrap section when not supplied")
    func noBootstrapperSection() {
        let opts = KSNSISTemplate.Options(
            appName: "Demo",
            version: "0.1.0",
            identifier: "dev.kalsae.demo",
            architecture: .x64,
            sourceDir: URL(fileURLWithPath: "C:/tmp/Demo"))
        let body = KSNSISTemplate.render(opts)
        #expect(!body.contains("/silent /install"))
    }

    @Test("runNSIS writes .nsi script and warns when makensis missing")
    func runNSISWritesScript() throws {
        let fm = FileManager.default
        let root = uniqueDir(suffix: "run")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let sourceDir = root.appendingPathComponent("Demo-1.2.3-x64")
        try makeSourceTree(at: sourceDir)

        let opts = KSNSISTemplate.Options(
            appName: "Demo",
            version: "1.2.3",
            identifier: "dev.kalsae.demo",
            architecture: .x64,
            sourceDir: sourceDir)

        let report = try KSPackager.runNSIS(opts)
        // The .nsi must always be written next to the source dir.
        #expect(fm.fileExists(atPath: report.scriptPath))
        let contents = try String(contentsOfFile: report.scriptPath, encoding: .utf8)
        #expect(contents.contains("!define APP_NAME \"Demo\""))
        // Compilation may or may not happen depending on host's makensis presence;
        // both branches are valid — but if no installer was produced, we expect a warning.
        if report.installerPath == nil {
            #expect(!report.warnings.isEmpty)
        }
    }
}
