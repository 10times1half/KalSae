import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSFSScope+Match")
struct KSFSScopeMatchTests {
    private func ctx(app: String = "/app", home: String = "/home/u") -> KSFSScope.ExpansionContext {
        .init(app: app, home: home, docs: "/home/u/Documents", temp: "/tmp")
    }

    private func makeTempRoot() throws -> (fileManager: FileManager, root: URL, allowed: URL) {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kalsae-fs-scope-\(UUID().uuidString)")
        let allowed = root.appendingPathComponent("allowed")
        try fileManager.createDirectory(at: allowed, withIntermediateDirectories: true)
        return (fileManager, root, allowed)
    }

    @Test("Single * does not cross path separator")
    func starNoSlash() {
        #expect(KSFSScope.glob(pattern: "/a/*", matches: "/a/b"))
        #expect(!KSFSScope.glob(pattern: "/a/*", matches: "/a/b/c"))
    }

    @Test("Double ** crosses any number of separators")
    func doubleStarCrosses() {
        #expect(KSFSScope.glob(pattern: "/a/**", matches: "/a/b/c/d"))
        #expect(KSFSScope.glob(pattern: "/a/**", matches: "/a/b"))
        #expect(!KSFSScope.glob(pattern: "/a/**", matches: "/x/y"))
    }

    @Test("? matches single non-slash")
    func questionMark() {
        #expect(KSFSScope.glob(pattern: "/a/?", matches: "/a/b"))
        #expect(!KSFSScope.glob(pattern: "/a/?", matches: "/a/bc"))
        #expect(!KSFSScope.glob(pattern: "/a/?", matches: "/a/b/c"))
    }

    @Test("Placeholder expansion replaces $APP/$HOME/$DOCS/$TEMP")
    func expansion() {
        let c = ctx(app: "/install", home: "/home/u")
        #expect(KSFSScope.expand("$APP/conf", in: c) == "/install/conf")
        #expect(KSFSScope.expand("$HOME/x", in: c) == "/home/u/x")
        #expect(KSFSScope.expand("$DOCS/y", in: c) == "/home/u/Documents/y")
        #expect(KSFSScope.expand("$TEMP/z", in: c) == "/tmp/z")
    }

    @Test("permits expands patterns and walks deny→allow")
    func permits() {
        let scope = KSFSScope(
            allow: ["$DOCS/kalsaeDemo/**"],
            deny: ["$DOCS/kalsaeDemo/secret/**"])
        let c = ctx()
        #expect(scope.permits(absolutePath: "/home/u/Documents/kalsaeDemo/foo.txt", in: c))
        #expect(scope.permits(absolutePath: "/home/u/Documents/kalsaeDemo/sub/dir/foo.txt", in: c))
        #expect(!scope.permits(absolutePath: "/home/u/Documents/kalsaeDemo/secret/passwords.txt", in: c))
        #expect(!scope.permits(absolutePath: "/home/u/Documents/other/foo.txt", in: c))
    }

    @Test("Empty allow denies every path")
    func emptyAllow() {
        let scope = KSFSScope()
        let c = ctx()
        #expect(!scope.permits(absolutePath: "/home/u/anything", in: c))
    }

    @Test("Empty deny array does not affect allow matching")
    func emptyDenyDoesNotBlock() {
        let scope = KSFSScope(
            allow: ["$DOCS/**"],
            deny: [])
        let c = ctx()
        #expect(scope.permits(absolutePath: "/home/u/Documents/foo.txt", in: c))
        #expect(scope.permits(absolutePath: "/home/u/Documents/sub/bar.txt", in: c))
    }

    @Test("Symlink escaping an allowed directory is denied")
    func deniesResolvedSymlinkEscape() throws {
        let (fileManager, root, allowed) = try makeTempRoot()
        let outside = root.appendingPathComponent("outside")
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let link = allowed.appendingPathComponent("escape")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: outside)

        let scope = KSFSScope(allow: ["\(allowed.path)/**"])
        let context = KSFSScope.ExpansionContext(
            app: root.path,
            home: root.path,
            docs: root.path,
            temp: root.path)

        #expect(
            !scope.permits(
                absolutePath: link.appendingPathComponent("secret.txt").path,
                in: context))
    }

    @Test("Symlink staying inside an allowed directory remains permitted")
    func allowsResolvedSymlinkInsideScope() throws {
        let (fileManager, root, allowed) = try makeTempRoot()
        let nested = allowed.appendingPathComponent("nested")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let link = allowed.appendingPathComponent("alias")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: nested)

        let scope = KSFSScope(allow: ["\(allowed.path)/**"])
        let context = KSFSScope.ExpansionContext(
            app: root.path,
            home: root.path,
            docs: root.path,
            temp: root.path)

        #expect(
            scope.permits(
                absolutePath: link.appendingPathComponent("note.txt").path,
                in: context))
    }
}
