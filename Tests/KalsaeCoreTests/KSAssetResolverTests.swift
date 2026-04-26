import Testing
import Foundation
@testable import KalsaeCore

@Suite("KSAssetResolver")
struct KSAssetResolverTests {
    /// Windows에서 Defender/검색 인덱서가 새로 만든 파일에 잠시 핸들을 걸어
    /// `atomically: true`(temp + rename) 경로가 ERROR_SHARING_VIOLATION(32)으로
    /// 실패하는 경우가 있다. 비원자적 쓰기 + 짧은 백오프 재시도로 우회한다.
    private static func writeWithRetry(_ string: String, to url: URL) throws {
        var lastError: (any Error)?
        for attempt in 0..<5 {
            do {
                try string.write(to: url, atomically: false, encoding: .utf8)
                return
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.05 * Double(attempt + 1))
            }
        }
        throw lastError!
    }

    /// Builds a throwaway asset directory containing a handful of files
    /// with known contents. Returned URL is the resolver root.
    private func makeFixture() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("KSAssetResolverTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        try Self.writeWithRetry("<!doctype html><title>Hi</title>",
            to: root.appendingPathComponent("index.html"))
        try Self.writeWithRetry("body{}",
            to: root.appendingPathComponent("app.css"))

        let subdir = root.appendingPathComponent("sub")
        try fm.createDirectory(at: subdir, withIntermediateDirectories: true)
        try Self.writeWithRetry("export const n = 1;",
            to: subdir.appendingPathComponent("m.js"))
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
