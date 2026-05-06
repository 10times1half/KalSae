import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSResourceSyncManager")
struct ResourceSyncManagerTests {

    private func uniqueDir(_ tag: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ks-syncmgr-\(UUID().uuidString)-\(tag)")
    }

    private func write(_ s: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try s.write(to: url, atomically: false, encoding: .utf8)
    }

    @Test("overlaps detects identical paths")
    func overlapIdentical() {
        let a = URL(fileURLWithPath: "/tmp/x/y")
        #expect(KSResourceSyncManager.overlaps(distURL: a, resourcesURL: a))
    }

    @Test("overlaps detects nesting in either direction")
    func overlapNested() {
        let parent = URL(fileURLWithPath: "/tmp/proj/Resources")
        let child = URL(fileURLWithPath: "/tmp/proj/Resources/dist")
        #expect(KSResourceSyncManager.overlaps(distURL: parent, resourcesURL: child))
        #expect(KSResourceSyncManager.overlaps(distURL: child, resourcesURL: parent))
    }

    @Test("overlaps returns false for sibling directories")
    func overlapSiblings() {
        let a = URL(fileURLWithPath: "/tmp/proj/dist")
        let b = URL(fileURLWithPath: "/tmp/proj/Resources")
        #expect(!KSResourceSyncManager.overlaps(distURL: a, resourcesURL: b))
    }

    @Test("sync copies new files into Resources")
    func syncCopiesNewFiles() throws {
        let dist = uniqueDir("dist")
        let resources = uniqueDir("res")
        defer {
            try? FileManager.default.removeItem(at: dist)
            try? FileManager.default.removeItem(at: resources)
        }
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try write("<html></html>", to: dist.appendingPathComponent("index.html"))
        try write("body{}", to: dist.appendingPathComponent("css/app.css"))

        let report = try KSResourceSyncManager.sync(distURL: dist, resourcesURL: resources)

        #expect(report.copied == 2)
        #expect(report.failed == 0)
        #expect(FileManager.default.fileExists(atPath: resources.appendingPathComponent("index.html").path))
        #expect(FileManager.default.fileExists(atPath: resources.appendingPathComponent("css/app.css").path))
    }

    @Test("sync removes orphan files but preserves kalsae.json")
    func syncRemovesOrphans() throws {
        let dist = uniqueDir("dist")
        let resources = uniqueDir("res")
        defer {
            try? FileManager.default.removeItem(at: dist)
            try? FileManager.default.removeItem(at: resources)
        }
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try write("hi", to: dist.appendingPathComponent("keep.txt"))
        try write("orphan", to: resources.appendingPathComponent("gone.txt"))
        try write("{}", to: resources.appendingPathComponent("kalsae.json"))

        let report = try KSResourceSyncManager.sync(distURL: dist, resourcesURL: resources)

        #expect(report.removed == 1)
        #expect(report.copied == 1)
        // kalsae.json must survive
        #expect(FileManager.default.fileExists(atPath: resources.appendingPathComponent("kalsae.json").path))
        #expect(!FileManager.default.fileExists(atPath: resources.appendingPathComponent("gone.txt").path))
    }

    @Test("sync skipped when dist overlaps resources")
    func syncSkipsOverlap() throws {
        let resources = uniqueDir("res-overlap")
        defer { try? FileManager.default.removeItem(at: resources) }
        let dist = resources.appendingPathComponent("nested")
        try write("x", to: dist.appendingPathComponent("a.txt"))

        let report = try KSResourceSyncManager.sync(distURL: dist, resourcesURL: resources)

        #expect(report.copied == 0)
        #expect(report.removed == 0)
        #expect(report.skippedReason?.contains("overlaps") == true)
    }

    @Test("sync returns skipped reason when resources directory missing")
    func syncSkipsMissingResources() throws {
        let dist = uniqueDir("dist")
        let resources = uniqueDir("missing")  // not created
        defer { try? FileManager.default.removeItem(at: dist) }
        try write("x", to: dist.appendingPathComponent("a.txt"))

        let report = try KSResourceSyncManager.sync(distURL: dist, resourcesURL: resources)
        #expect(report.skippedReason != nil)
        #expect(report.didMutate == false)
    }
}
