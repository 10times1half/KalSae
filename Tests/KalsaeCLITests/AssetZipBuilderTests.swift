import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSAssetZipBuilder")
struct AssetZipBuilderTests {
    private func makeFixture() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("KSAssetZipBuilderTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "<html>hi</html>".write(
            to: root.appendingPathComponent("index.html"),
            atomically: false,
            encoding: .utf8)
        let assets = root.appendingPathComponent("assets")
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        try "console.log('ok')".write(
            to: assets.appendingPathComponent("app.js"),
            atomically: false,
            encoding: .utf8)
        return root
    }

    @Test("build packages frontend dist into zip data with relative file list")
    func buildZipData() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let report = try KSAssetZipBuilder.build(from: root)

        #expect(report.fileCount == 2)
        #expect(report.totalUncompressedBytes > 0)
        #expect(report.zipData.count > 0)
        #expect(report.relativePaths == ["assets/app.js", "index.html"])
    }

    @Test("build throws when source directory is missing")
    func missingSourceThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")

        #expect(throws: (any Error).self) {
            _ = try KSAssetZipBuilder.build(from: missing)
        }
    }
}
