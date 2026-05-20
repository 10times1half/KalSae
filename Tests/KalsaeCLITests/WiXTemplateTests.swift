import Foundation
import Testing

@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("KSWiXTemplate — .wxs rendering")
struct WiXTemplateTests {

    private func makeStagingDir() throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(
            "kalsae-wix-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let stage = base.appendingPathComponent("MyApp-1.0.0-x64", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        try Data("exe".utf8).write(to: stage.appendingPathComponent("MyApp.exe"))
        let sub = stage.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("html".utf8).write(to: sub.appendingPathComponent("index.html"))
        return stage
    }

    @Test("normalizeVersion clamps to MSI 4-part 0-65535 form")
    func normalizesVersion() {
        #expect(KSWiXTemplate.normalizeVersion("1.2.3") == "1.2.3")
        #expect(KSWiXTemplate.normalizeVersion("1.2.3.4") == "1.2.3.4")
        #expect(KSWiXTemplate.normalizeVersion("1.2.3-beta") == "1.2.3")
        #expect(KSWiXTemplate.normalizeVersion("99999.0.0") == "65535.0.0")
        #expect(KSWiXTemplate.normalizeVersion("not-a-version") == "0.0.0")
    }

    @Test("render emits Product + Package + MajorUpgrade + Feature")
    func rendersCoreElements() throws {
        let stage = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: stage.deletingLastPathComponent()) }
        let upgrade = UUID(uuidString: "11111111-2222-5333-9444-555555555555")!
        let opts = KSWiXTemplate.Options(
            appName: "MyApp",
            version: "1.0.0",
            identifier: "dev.example.myapp",
            publisher: "Example",
            architecture: .x64,
            sourceDir: stage,
            productCode: UUID(),
            upgradeCode: upgrade,
            iconPath: nil,
            allowDowngrades: true)
        let xml = try KSWiXTemplate.render(opts)
        #expect(xml.contains("<Product"))
        #expect(xml.contains("Name=\"MyApp\""))
        #expect(
            xml.contains("UpgradeCode=\"11111111-2222-5333-9444-555555555555\"")
                || xml.contains("UpgradeCode=\"\(upgrade.uuidString)\""))
        #expect(xml.contains("<MajorUpgrade"))
        #expect(xml.contains("<Feature"))
        #expect(xml.contains("MyApp.exe"))
    }

    @Test("render is deterministic across invocations for the same inputs")
    func deterministicRender() throws {
        let stage = try makeStagingDir()
        defer { try? FileManager.default.removeItem(at: stage.deletingLastPathComponent()) }
        let upgrade = UUID(uuidString: "AAAAAAAA-BBBB-5CCC-9DDD-EEEEEEEEEEEE")!
        let productCode = UUID(uuidString: "12345678-1234-5234-9234-123456789ABC")!
        let opts = KSWiXTemplate.Options(
            appName: "MyApp",
            version: "1.0.0",
            identifier: "dev.example.myapp",
            publisher: "Example",
            architecture: .x64,
            sourceDir: stage,
            productCode: productCode,
            upgradeCode: upgrade,
            iconPath: nil,
            allowDowngrades: true)
        let a = try KSWiXTemplate.render(opts)
        let b = try KSWiXTemplate.render(opts)
        #expect(a == b)
    }
}
