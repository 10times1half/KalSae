import Testing
import Foundation
@testable import KalsaeCore

@Suite("KSAssetResolver")
struct KSAssetResolverTests {
    /// Builds a throwaway asset directory containing a handful of files
    /// with known contents. Returned URL is the resolver root.
    private func makeFixture() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("KSAssetResolverTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        try "<!doctype html><title>Hi</title>".write(
            to: root.appendingPathComponent("index.html"),
            atomically: true, encoding: .utf8)
        try "body{}".write(
            to: root.appendingPathComponent("app.css"),
            atomically: true, encoding: .utf8)

        let subdir = root.appendingPathComponent("sub")
        try fm.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "export const n = 1;".write(
            to: subdir.appendingPathComponent("m.js"),
            atomically: true, encoding: .utf8)
        return root
    }

    @Test("Serves index for empty and '/' paths")
    func indexFallback() throws {
        let root = try makeFixture()
        let r = KSAssetResolver(root: root)

        let viaEmpty = try r.resolve(path: "")
        #expect(String(data: viaEmpty.data, encoding: .utf8)?.contains("Hi") == true)
        #expect(viaEmpty.mimeType.hasPrefix("text/html"))

        let viaSlash = try r.resolve(path: "/")
        #expect(String(data: viaSlash.data, encoding: .utf8)?.contains("Hi") == true)
    }

    @Test("Resolves css and nested js with correct MIME")
    func mimeTypes() throws {
        let root = try makeFixture()
        let r = KSAssetResolver(root: root)

        let css = try r.resolve(path: "/app.css")
        #expect(css.mimeType.hasPrefix("text/css"))

        let js = try r.resolve(path: "sub/m.js")
        #expect(js.mimeType.hasPrefix("application/javascript"))
    }

    @Test("Rejects '..' traversal outside the root")
    func traversalRejected() throws {
        let root = try makeFixture()
        let r = KSAssetResolver(root: root)
        #expect(throws: KSError.self) {
            _ = try r.resolve(path: "../../etc/passwd")
        }
    }

    @Test("Rejects absolute paths")
    func absoluteRejected() throws {
        let root = try makeFixture()
        let r = KSAssetResolver(root: root)
        #expect(throws: KSError.self) {
            _ = try r.resolve(path: "//etc/passwd")
        }
    }

    @Test("Returns ioFailed for missing files inside the root")
    func missingFile() throws {
        let root = try makeFixture()
        let r = KSAssetResolver(root: root)
        do {
            _ = try r.resolve(path: "nope.txt")
            Issue.record("expected ioFailed")
        } catch {
            #expect(error.code == .ioFailed)
        }
    }

    @Test("KSContentType falls back to octet-stream for unknown ext")
    func unknownMime() {
        #expect(KSContentType.forExtension("xyz") == "application/octet-stream")
        #expect(KSContentType.forExtension("HTML").hasPrefix("text/html"))
    }
}
