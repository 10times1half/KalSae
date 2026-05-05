import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSPackager — macOS .app bundle")
struct PackagerMacTests {

    private func uniqueDir(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-mac-\(UUID().uuidString)-\(suffix)")
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    @Test("Mac bundle has expected structure and Info.plist keys")
    func bundleStructure() throws {
        let fm = FileManager.default
        let work = uniqueDir(suffix: "structure")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // Fake executable, config, dist
        let exe = work.appendingPathComponent("Demo")
        try writeText("#!/bin/sh\necho hi\n", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText("{\"app\":{\"name\":\"Demo\"}}", to: config)
        let dist = work.appendingPathComponent("dist")
        try fm.createDirectory(at: dist, withIntermediateDirectories: true)
        try writeText("<html></html>", to: dist.appendingPathComponent("index.html"))

        let output = work.appendingPathComponent("out")
        try fm.createDirectory(at: output, withIntermediateDirectories: true)

        let opts = KSPackager.MacOptions(
            executablePath: exe,
            configPath: config,
            frontendDist: dist,
            output: output,
            appName: "Demo",
            version: "1.2.3",
            identifier: "dev.kalsae.demo",
            architecture: .arm64,
            zip: false)

        let report = try KSPackager.runMac(opts)
        let bundle = URL(fileURLWithPath: report.outputPath)

        #expect(bundle.lastPathComponent == "Demo.app")
        #expect(fm.fileExists(atPath: bundle.appendingPathComponent("Contents/MacOS/Demo").path))
        #expect(fm.fileExists(atPath: bundle.appendingPathComponent("Contents/Info.plist").path))
        #expect(fm.fileExists(atPath: bundle.appendingPathComponent("Contents/Resources/Kalsae.json").path))
        #expect(fm.fileExists(atPath: bundle.appendingPathComponent("Contents/Resources/index.html").path))

        let plist = try String(
            contentsOf: bundle.appendingPathComponent("Contents/Info.plist"), encoding: .utf8)
        #expect(plist.contains("<string>dev.kalsae.demo</string>"))
        #expect(plist.contains("<string>1.2.3</string>"))
        #expect(plist.contains("CFBundleExecutable"))
        #expect(plist.contains("NSHighResolutionCapable"))
        #expect(plist.contains("LSMinimumSystemVersion"))
    }

    @Test("Mac bundle warns when frontend dist is missing")
    func missingDist() throws {
        let fm = FileManager.default
        let work = uniqueDir(suffix: "no-dist")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let exe = work.appendingPathComponent("App")
        try writeText("x", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText("{}", to: config)

        let output = work.appendingPathComponent("out")
        try fm.createDirectory(at: output, withIntermediateDirectories: true)

        let opts = KSPackager.MacOptions(
            executablePath: exe,
            configPath: config,
            frontendDist: nil,
            output: output,
            appName: "App",
            version: "0.1.0",
            identifier: "dev.kalsae.app",
            architecture: .universal)

        let report = try KSPackager.runMac(opts)
        #expect(report.warnings.contains { $0.contains("Frontend dist") })
    }

    @Test("Mac bundle codesign identity surfaces a warning until implemented")
    func codesignHookWarns() throws {
        let fm = FileManager.default
        let work = uniqueDir(suffix: "codesign")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let exe = work.appendingPathComponent("App")
        try writeText("x", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText("{}", to: config)

        let output = work.appendingPathComponent("out")
        try fm.createDirectory(at: output, withIntermediateDirectories: true)

        let opts = KSPackager.MacOptions(
            executablePath: exe,
            configPath: config,
            frontendDist: nil,
            output: output,
            appName: "App",
            version: "0.1.0",
            identifier: "dev.kalsae.app",
            architecture: .arm64,
            codesignIdentity: "Developer ID Application: Acme")

        let report = try KSPackager.runMac(opts)
        #expect(report.warnings.contains { $0.contains("codesign") || $0.contains("Code signing") })
    }
}
