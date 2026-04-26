import Testing
import Foundation
@testable import KalsaeCLICore

#if os(Windows)

@Suite("KSPackager — zip helper")
struct PackagerZipTests {

    private func makeTree(at root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.writeWithRetry("hello",
                                to: root.appendingPathComponent("a.txt"))
        let sub = root.appendingPathComponent("nested")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try Self.writeWithRetry("world",
                                to: sub.appendingPathComponent("b.txt"))
    }

    /// Windows에서 Defender/검색 인덱서가 새로 만든 파일에 잠시 핸들을 걸어
    /// `atomically: true`(temp + rename) 경로가 ERROR_SHARING_VIOLATION(32)으로
    /// 실패하는 경우가 있다. 비원자적 쓰기 + 짧은 백오프 재시도로 우회한다.
    private static func writeWithRetry(_ string: String, to url: URL) throws {
        var lastError: Error?
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

    private func uniqueDir(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-pkg-\(UUID().uuidString)-\(suffix)")
    }

    @Test("createZip handles plain paths")
    func plainPath() throws {
        let src = uniqueDir(suffix: "plain")
        let archive = uniqueDir(suffix: "plain").appendingPathExtension("zip")
        try makeTree(at: src)
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: archive)
        }

        try KSPackager.createZip(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
        let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > 0)
    }

    @Test("createZip handles paths with spaces")
    func spaceInPath() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae pkg \(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)
        let src = parent.appendingPathComponent("source dir")
        let archive = parent.appendingPathComponent("out file.zip")
        try makeTree(at: src)
        defer { try? FileManager.default.removeItem(at: parent) }

        try KSPackager.createZip(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("createZip handles paths with single quotes")
    func singleQuotePath() throws {
        // PowerShell 단일따옴표 인젝션 회귀 가드: env-var 경로 전달이 정확히
        // 동작하는지 검증.
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae'pkg'\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)
        let src = parent.appendingPathComponent("o'reilly")
        let archive = parent.appendingPathComponent("a'b.zip")
        try makeTree(at: src)
        defer { try? FileManager.default.removeItem(at: parent) }

        try KSPackager.createZip(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("createZip handles unicode paths")
    func unicodePath() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("칼새-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)
        let src = parent.appendingPathComponent("자료")
        let archive = parent.appendingPathComponent("결과.zip")
        try makeTree(at: src)
        defer { try? FileManager.default.removeItem(at: parent) }

        try KSPackager.createZip(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("createZip overwrites existing archive")
    func overwriteExisting() throws {
        let src = uniqueDir(suffix: "ow-src")
        let archive = uniqueDir(suffix: "ow-dst").appendingPathExtension("zip")
        try makeTree(at: src)
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: archive)
        }

        try KSPackager.createZip(from: src, to: archive)
        let firstSize = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        // 두 번째 실행: 기존 zip 위에 다시 만들 때 PowerShell 측에서
        // Remove-Item으로 처리하므로 실패하지 않아야 한다.
        try KSPackager.createZip(from: src, to: archive)
        let secondSize = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(firstSize > 0 && secondSize > 0)
    }

    @Test("createZipAsync mirrors createZip outcome")
    func asyncVariant() async throws {
        let src = uniqueDir(suffix: "async")
        let archive = uniqueDir(suffix: "async").appendingPathExtension("zip")
        try makeTree(at: src)
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: archive)
        }

        try await KSPackager.createZipAsync(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }
}

#endif
