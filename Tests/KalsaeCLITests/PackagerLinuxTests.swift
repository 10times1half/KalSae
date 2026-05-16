import Foundation
import Testing

@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("KSPackager ??Linux packaging (RFC-009)")
struct PackagerLinuxTests {

    private func uniqueDir(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-linux-\(UUID().uuidString)-\(suffix)")
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    private func makeFixture(suffix: String, formats: Set<KSPackager.LinuxFormat>) throws
        -> (work: URL, opts: KSPackager.LinuxOptions)
    {
        let fm = FileManager.default
        let work = uniqueDir(suffix)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let exe = work.appendingPathComponent("MyApp")
        try writeText("ELF-fake", to: exe)

        let config = work.appendingPathComponent("kalsae.json")
        try writeText(
            #"{"app":{"name":"Demo"},"build":{"frontendDist":"dist"},"security":{"devtools":true}}"#,
            to: config)

        let dist = work.appendingPathComponent("dist")
        try fm.createDirectory(at: dist, withIntermediateDirectories: true)
        try writeText("<!doctype html><title>x</title>", to: dist.appendingPathComponent("index.html"))

        let output = work.appendingPathComponent("out")

        let opts = KSPackager.LinuxOptions(
            executablePath: exe,
            configPath: config,
            frontendDist: dist,
            output: output,
            appName: "Demo App",
            version: "1.2.3",
            identifier: "com.example.demo",
            architecture: .x86_64,
            formats: formats,
            iconPath: nil,
            maintainer: "Demo Dev <dev@example.com>")
        return (work, opts)
    }

    // MARK: - 寃利?
    @Test("identifier validation rejects bad reverse-DNS")
    func identifierValidation() {
        #expect(KSPackager.isValidLinuxIdentifier("com.example.demo"))
        #expect(KSPackager.isValidLinuxIdentifier("io.kalsae.app-name"))
        #expect(!KSPackager.isValidLinuxIdentifier("demo"))                    // no dot
        #expect(!KSPackager.isValidLinuxIdentifier("Com.Example.Demo"))        // uppercase
        #expect(!KSPackager.isValidLinuxIdentifier("1com.example.demo"))       // starts with digit
        #expect(!KSPackager.isValidLinuxIdentifier(""))
    }

    @Test("deb version validation")
    func debVersionValidation() {
        #expect(KSPackager.isValidDebVersion("1.2.3"))
        #expect(KSPackager.isValidDebVersion("0.1.0-alpha"))
        #expect(KSPackager.isValidDebVersion("2024.01.15+build.42"))
        #expect(!KSPackager.isValidDebVersion("v1.0"))      // leading 'v'
        #expect(!KSPackager.isValidDebVersion(""))
        #expect(!KSPackager.isValidDebVersion("1.0 beta"))  // whitespace
    }

    @Test("missing maintainer for .deb format throws")
    func debRequiresMaintainer() throws {
        let (_, baseOpts) = try makeFixture(suffix: "no-maint", formats: [.deb])
        var opts = baseOpts
        opts.maintainer = nil
        #expect(throws: KSError.self) {
            _ = try KSPackager.runLinux(opts)
        }
    }

    @Test("empty formats throws")
    func emptyFormatsThrows() throws {
        let (_, base) = try makeFixture(suffix: "empty", formats: [.tarball])
        var opts = base
        opts.formats = []
        #expect(throws: KSError.self) {
            _ = try KSPackager.runLinux(opts)
        }
    }

    // MARK: - .desktop ?뚮뜑留?
    @Test("desktop file renders required keys + escapes")
    func desktopRender() {
        let txt = KSPackager.renderLinuxDesktopFile(
            appName: "My App\nName",
            execCommand: "/usr/bin/myapp",
            iconName: "myapp",
            identifier: "com.example.myapp")
        #expect(txt.hasPrefix("[Desktop Entry]"))
        #expect(txt.contains("Type=Application"))
        #expect(txt.contains("Name=My App\\nName"))   // newline escaped
        #expect(txt.contains("Exec=/usr/bin/myapp"))
        #expect(txt.contains("Icon=myapp"))
        #expect(txt.contains("Terminal=false"))
        #expect(txt.contains("StartupWMClass=com.example.myapp"))
    }

    @Test("desktop file omits Icon when not provided")
    func desktopNoIcon() {
        let txt = KSPackager.renderLinuxDesktopFile(
            appName: "A", execCommand: "a", iconName: nil, identifier: "com.a.b")
        #expect(!txt.contains("Icon="))
    }

    // MARK: - DEBIAN/control ?뚮뜑留?
    @Test("deb control declares system GTK/WebKitGTK Depends (no bundling)")
    func debControlRender() throws {
        let (_, opts) = try makeFixture(suffix: "ctrl", formats: [.deb])
        let txt = KSPackager.renderDebControl(opts: opts, installedSizeKB: 2048)
        #expect(txt.contains("Package: com.example.demo"))
        #expect(txt.contains("Version: 1.2.3"))
        #expect(txt.contains("Architecture: amd64"))
        #expect(txt.contains("Maintainer: Demo Dev <dev@example.com>"))
        #expect(txt.contains("Installed-Size: 2048"))
        // ?듭떖: ?쒖뒪???쇱씠釉뚮윭由щ? Depends 濡??좎뼵 ??Kalsae ??"OS ?붿쭊 ?ъ궗?? 泥좏븰 ?뺤떇??利앸챸.
        #expect(txt.contains("libgtk-4-1"))
        #expect(txt.contains("libwebkitgtk-6.0-4"))
        #expect(txt.contains("libsoup-3.0-0"))
        // CRLF 媛 ?꾨땶 LF + 留덉?留?鍮?以?
        #expect(txt.hasSuffix("\n\n"))
    }

    // MARK: - AppRun

    @Test("AppImage AppRun is POSIX sh + cd to share + exec exe")
    func appRunRender() {
        let txt = KSPackager.renderAppImageAppRun(exeName: "MyApp")
        #expect(txt.hasPrefix("#!/bin/sh"))
        #expect(txt.contains("$APPDIR") || txt.contains("HERE"))
        #expect(txt.contains("exec"))
        #expect(txt.contains("MyApp"))
    }

    // MARK: - End-to-end emit (?몄뒪??OS 臾닿?)

    @Test("tarball format emits expected tree")
    func tarballEmit() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "tar", formats: [.tarball])
        let report = try KSPackager.runLinux(opts)

        let stagePrefix = work.appendingPathComponent("out/tarball/demo-app-1.2.3-linux-x86_64")
        #expect(fm.fileExists(atPath: stagePrefix.path))
        #expect(fm.fileExists(atPath: stagePrefix.appendingPathComponent("MyApp").path))
        #expect(fm.fileExists(atPath: stagePrefix.appendingPathComponent("kalsae.json").path))
        #expect(fm.fileExists(atPath: stagePrefix.appendingPathComponent("Resources/index.html").path))
        #expect(fm.fileExists(atPath: stagePrefix.appendingPathComponent("demo-app.desktop").path))
        #expect(fm.fileExists(atPath: stagePrefix.appendingPathComponent("INSTALL.md").path))
        // README ?덈궡臾몄씠 ?묒꽦?섏뼱????        #expect(fm.fileExists(atPath: work.appendingPathComponent("out/README.md").path))
        #expect(report.policy.contains("tarball"))

        // packaged kalsae.json: frontendDist="Resources", devtools off
        let cfg = try String(contentsOf: stagePrefix.appendingPathComponent("kalsae.json"), encoding: .utf8)
        #expect(cfg.contains("\"frontendDist\""))
        #expect(cfg.contains("Resources"))
    }

    @Test("deb format emits FHS tree with DEBIAN/control + launcher")
    func debEmit() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "deb", formats: [.deb])
        let report = try KSPackager.runLinux(opts)

        let debRoot = work.appendingPathComponent("out/deb/com.example.demo")
        #expect(fm.fileExists(atPath: debRoot.appendingPathComponent("DEBIAN/control").path))
        #expect(fm.fileExists(atPath: debRoot.appendingPathComponent("usr/bin/com.example.demo").path))
        #expect(fm.fileExists(atPath: debRoot.appendingPathComponent("usr/lib/com.example.demo/MyApp").path))
        #expect(fm.fileExists(atPath: debRoot.appendingPathComponent("usr/lib/com.example.demo/kalsae.json").path))
        #expect(fm.fileExists(atPath: debRoot.appendingPathComponent("usr/lib/com.example.demo/Resources/index.html").path))
        #expect(fm.fileExists(atPath: debRoot.appendingPathComponent("usr/share/applications/com.example.demo.desktop").path))

        let control = try String(contentsOf: debRoot.appendingPathComponent("DEBIAN/control"), encoding: .utf8)
        #expect(control.contains("libwebkitgtk-6.0-4"))

        let launcher = try String(contentsOf: debRoot.appendingPathComponent("usr/bin/com.example.demo"), encoding: .utf8)
        #expect(launcher.hasPrefix("#!/bin/sh"))
        #expect(launcher.contains("/usr/lib/com.example.demo"))
        #expect(report.policy.contains("deb"))
    }

    @Test("appImage format emits AppDir with AppRun + root .desktop")
    func appImageEmit() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "appim", formats: [.appImage])
        let report = try KSPackager.runLinux(opts)

        let appDir = work.appendingPathComponent("out/AppDir")
        #expect(fm.fileExists(atPath: appDir.appendingPathComponent("AppRun").path))
        #expect(fm.fileExists(atPath: appDir.appendingPathComponent("com.example.demo.desktop").path))
        #expect(fm.fileExists(atPath: appDir.appendingPathComponent("usr/bin/MyApp").path))
        #expect(fm.fileExists(atPath: appDir.appendingPathComponent("usr/share/Resources/index.html").path))
        #expect(fm.fileExists(atPath: appDir.appendingPathComponent("usr/share/kalsae.json").path))
        #expect(report.policy.contains("appimage"))
    }

    @Test("all three formats emit side-by-side")
    func multiFormatEmit() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(
            suffix: "all", formats: [.tarball, .deb, .appImage])
        let report = try KSPackager.runLinux(opts)
        #expect(fm.fileExists(atPath: work.appendingPathComponent("out/tarball").path))
        #expect(fm.fileExists(atPath: work.appendingPathComponent("out/deb").path))
        #expect(fm.fileExists(atPath: work.appendingPathComponent("out/AppDir").path))
        // policy ???뺣젹???щ㎎紐낆쓣 ?⑹퀜??媛吏?        #expect(report.policy == "linux-appimage+deb+tarball")
    }

    @Test("missing executable throws KSError")
    func missingExeThrows() throws {
        let (work, base) = try makeFixture(suffix: "noexe", formats: [.tarball])
        var opts = base
        opts.executablePath = work.appendingPathComponent("does-not-exist")
        #expect(throws: KSError.self) {
            _ = try KSPackager.runLinux(opts)
        }
    }
}
