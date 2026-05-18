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

    // MARK: - relativize

    @Test("relativize strips base prefix only")
    func relativizeStripsPrefixOnce() {
        let base = "/tmp/proj/dist"
        let path = "/tmp/proj/dist/assets/index.js"
        #expect(KSResourceSyncManager.relativize(path, base: base) == "assets/index.js")
    }

    /// 회귀: base가 path 내에서 두 번 등장할 때 (예: 사용자가 dist 폴더 안에
    /// 또 다른 dist 디렉터리를 둔 경우) 단순 `replacingOccurrences`는 안쪽
    /// 매치까지 같이 지워서 잘못된 상대 경로를 만든다 — prefix 한 번만 제거해야 한다.
    @Test("relativize handles base substring re-appearing in path")
    func relativizeDoesNotEatNestedBase() {
        let base = "/tmp/dist"
        let path = "/tmp/dist/dist/index.html"
        #expect(KSResourceSyncManager.relativize(path, base: base) == "dist/index.html")
    }

    @Test("relativize normalizes Windows backslashes")
    func relativizeNormalizesBackslashes() {
        let base = #"C:\proj\dist"#
        let path = #"C:\proj\dist\assets\app.js"#
        #expect(KSResourceSyncManager.relativize(path, base: base) == "assets/app.js")
    }

    @Test("relativize returns path unchanged when base is not a prefix")
    func relativizeNoPrefixPassthrough() {
        let result = KSResourceSyncManager.relativize("/foo/bar", base: "/baz")
        #expect(result == "foo/bar")
    }

    // MARK: - preserveResources (A1)

    @Test("preservedGlobs keeps matching leaf file from being pruned")
    func preserveGlobsKeepsLeafFile() throws {
        let dist = uniqueDir("dist")
        let resources = uniqueDir("res")
        defer {
            try? FileManager.default.removeItem(at: dist)
            try? FileManager.default.removeItem(at: resources)
        }
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try write("{}", to: resources.appendingPathComponent("selectors.json"))
        try write("orphan", to: resources.appendingPathComponent("gone.txt"))

        let report = try KSResourceSyncManager.sync(
            distURL: dist,
            resourcesURL: resources,
            preservedGlobs: ["selectors.json"])

        #expect(
            FileManager.default.fileExists(
                atPath: resources.appendingPathComponent("selectors.json").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: resources.appendingPathComponent("gone.txt").path))
        #expect(report.removed == 1)
        #expect(report.removedRels == ["gone.txt"])
    }

    @Test("preservedGlobs keeps subtree under ** pattern")
    func preserveGlobsKeepsSubtree() throws {
        let dist = uniqueDir("dist")
        let resources = uniqueDir("res")
        defer {
            try? FileManager.default.removeItem(at: dist)
            try? FileManager.default.removeItem(at: resources)
        }
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try write("//", to: resources.appendingPathComponent("scripts/a.js"))
        try write("//", to: resources.appendingPathComponent("scripts/sub/b.js"))
        try write("orphan", to: resources.appendingPathComponent("other.txt"))

        let report = try KSResourceSyncManager.sync(
            distURL: dist,
            resourcesURL: resources,
            preservedGlobs: ["scripts/**"])

        #expect(
            FileManager.default.fileExists(
                atPath: resources.appendingPathComponent("scripts/a.js").path))
        #expect(
            FileManager.default.fileExists(
                atPath: resources.appendingPathComponent("scripts/sub/b.js").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: resources.appendingPathComponent("other.txt").path))
        #expect(report.removedRels.contains("other.txt"))
        #expect(!report.removedRels.contains { $0.hasPrefix("scripts") })
    }

    @Test("noPrune skips orphan removal entirely")
    func noPruneSkipsOrphanRemoval() throws {
        let dist = uniqueDir("dist")
        let resources = uniqueDir("res")
        defer {
            try? FileManager.default.removeItem(at: dist)
            try? FileManager.default.removeItem(at: resources)
        }
        try FileManager.default.createDirectory(at: dist, withIntermediateDirectories: true)
        try write("orphan-a", to: resources.appendingPathComponent("a.txt"))
        try write("orphan-b", to: resources.appendingPathComponent("nested/b.txt"))

        let report = try KSResourceSyncManager.sync(
            distURL: dist,
            resourcesURL: resources,
            noPrune: true)

        #expect(report.removed == 0)
        #expect(report.removedRels.isEmpty)
        #expect(
            FileManager.default.fileExists(
                atPath: resources.appendingPathComponent("a.txt").path))
        #expect(
            FileManager.default.fileExists(
                atPath: resources.appendingPathComponent("nested/b.txt").path))
    }
}
