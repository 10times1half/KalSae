import Foundation
import Testing

@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("KSPackager - iOS .app bundle (Phase iOS-Stable v3)")
struct PackagerIOSAppBundleTests {

    private func uniqueDir(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-ios-app-\(UUID().uuidString)-\(suffix)")
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    private func makeFixture(suffix: String) throws -> (work: URL, opts: KSPackager.IOSOptions) {
        let fm = FileManager.default
        let work = uniqueDir(suffix: suffix)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let exe = work.appendingPathComponent("DemoApp")
        try writeText("MachO-fake", to: exe)

        let config = work.appendingPathComponent("kalsae.json")
        try writeText(
            #"{"app":{"name":"Demo"},"build":{"frontendDist":"dist"},"security":{"devtools":true}}"#,
            to: config)

        let dist = work.appendingPathComponent("dist")
        try fm.createDirectory(at: dist, withIntermediateDirectories: true)
        try writeText(
            "<!doctype html><title>x</title>",
            to: dist.appendingPathComponent("index.html"))
        try writeText(
            "console.log('hi')",
            to: dist.appendingPathComponent("app.js"))

        let output = work.appendingPathComponent("out")

        let opts = KSPackager.IOSOptions(
            executablePath: exe,
            configPath: config,
            frontendDist: dist,
            output: output,
            appName: "Demo App",
            version: "1.2.3",
            identifier: "com.example.demo",
            bundleVersion: "42",
            minimumOSVersion: "16.0",
            architecture: .arm64,
            iconPath: nil,
            deepLinkSchemes: ["myapp", "demo"])
        return (work, opts)
    }

    // MARK: - Happy path

    @Test(".app bundle has expected layout")
    func bundleStructure() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "structure")
        defer { try? fm.removeItem(at: work) }

        let report = try KSPackager.runIOS(opts)
        let app = URL(fileURLWithPath: report.outputPath)

        #expect(report.policy == "ios-app-bundle")
        #expect(app.lastPathComponent == "Demo App.app")
        // Info.plist + executable + kalsae.json + frontend at root.
        #expect(fm.fileExists(atPath: app.appendingPathComponent("Info.plist").path))
        #expect(fm.fileExists(atPath: app.appendingPathComponent("kalsae.json").path))
        #expect(fm.fileExists(atPath: app.appendingPathComponent("index.html").path))
        #expect(fm.fileExists(atPath: app.appendingPathComponent("app.js").path))
        // Executable name is sanitized (space ??"_").
        #expect(fm.fileExists(atPath: app.appendingPathComponent("Demo_App").path))
    }

    @Test("Info.plist contains required security/version/identifier keys")
    func infoPlistContents() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "plist")
        defer { try? fm.removeItem(at: work) }

        let report = try KSPackager.runIOS(opts)
        let plistURL = URL(fileURLWithPath: report.outputPath)
            .appendingPathComponent("Info.plist")
        let text = try String(contentsOf: plistURL, encoding: .utf8)

        // 보안: ATS off-by-default 강제 (RFC-008 v4.2).
        #expect(text.contains("<key>NSAppTransportSecurity</key>"))
        #expect(text.contains("<key>NSAllowsArbitraryLoads</key>"))
        // 버전/배포 관련 min OS.
        #expect(text.contains("<key>CFBundleIdentifier</key>"))
        #expect(text.contains("<string>com.example.demo</string>"))
        #expect(text.contains("<key>CFBundleShortVersionString</key>"))
        #expect(text.contains("<string>1.2.3</string>"))
        #expect(text.contains("<key>CFBundleVersion</key>"))
        #expect(text.contains("<string>42</string>"))
        #expect(text.contains("<key>MinimumOSVersion</key>"))
        #expect(text.contains("<string>16.0</string>"))
        // Launch screen + iPhone-required.
        #expect(text.contains("<key>UILaunchScreen</key>"))
        #expect(text.contains("<key>LSRequiresIPhoneOS</key>"))
        // 딥링크 스키마.
        #expect(text.contains("<key>CFBundleURLTypes</key>"))
        #expect(text.contains("<string>myapp</string>"))
        #expect(text.contains("<string>demo</string>"))
    }

    @Test("Packaged kalsae.json is sanitized (frontendDist=., devtools=false)")
    func sanitizedConfig() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "config")
        defer { try? fm.removeItem(at: work) }

        let report = try KSPackager.runIOS(opts)
        let configURL = URL(fileURLWithPath: report.outputPath)
            .appendingPathComponent("kalsae.json")
        let data = try Data(contentsOf: configURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let build = json?["build"] as? [String: Any]
        #expect(build?["frontendDist"] as? String == ".")

        let security = json?["security"] as? [String: Any]
        #expect((security?["devtools"] as? Bool) == false)
    }

    // MARK: - Validation

    @Test("rejects missing executable")
    func rejectsMissingExe() throws {
        let fm = FileManager.default
        let fixture = try makeFixture(suffix: "noexe")
        let work = fixture.work
        var opts = fixture.opts
        defer { try? fm.removeItem(at: work) }
        opts.executablePath = work.appendingPathComponent("does-not-exist")
        do {
            _ = try KSPackager.runIOS(opts)
            Issue.record("expected throw")
        } catch let e as KSError {
            #expect(e.code == .configInvalid)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("rejects invalid bundle identifier")
    func rejectsInvalidBundleID() throws {
        let fm = FileManager.default
        let fixture = try makeFixture(suffix: "badid")
        let work = fixture.work
        var opts = fixture.opts
        defer { try? fm.removeItem(at: work) }
        opts.identifier = "no-dot-id"
        do {
            _ = try KSPackager.runIOS(opts)
            Issue.record("expected throw")
        } catch let e as KSError {
            #expect(e.code == .configInvalid)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("isValidIOSBundleIdentifier accepts/rejects expected forms")
    func bundleIDValidator() {
        #expect(KSPackager.isValidIOSBundleIdentifier("com.example.app"))
        #expect(KSPackager.isValidIOSBundleIdentifier("com.example.my-app"))
        #expect(KSPackager.isValidIOSBundleIdentifier("io.kalsae.demo123"))
        #expect(!KSPackager.isValidIOSBundleIdentifier(""))
        #expect(!KSPackager.isValidIOSBundleIdentifier("noDot"))
        #expect(!KSPackager.isValidIOSBundleIdentifier("com..example"))
        #expect(!KSPackager.isValidIOSBundleIdentifier("-com.example"))
        #expect(!KSPackager.isValidIOSBundleIdentifier("com.example."))
        #expect(!KSPackager.isValidIOSBundleIdentifier("com.exa mple.app"))
    }

    @Test("sanitizedExecutableName replaces unsafe chars")
    func executableNameSanitization() {
        #expect(KSPackager.sanitizedExecutableName("DemoApp") == "DemoApp")
        #expect(KSPackager.sanitizedExecutableName("Demo App") == "Demo_App")
        #expect(KSPackager.sanitizedExecutableName("My/Cool*App") == "My_Cool_App")
        #expect(KSPackager.sanitizedExecutableName("") == "App")
    }
}
