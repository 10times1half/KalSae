import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSAssetWatcher — fingerprint + change detection")
struct KSAssetWatcherTests {
    private static func tmpRoot() -> URL {
        let r = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-watcher-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: r, withIntermediateDirectories: true)
        return r
    }

    @Test("fingerprint이 동일 콘텐츠에서 동일하다")
    func stableFingerprint() throws {
        let root = Self.tmpRoot()
        try "hello".write(
            to: root.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8)
        let w = KSAssetWatcher(root: root)
        let fp1 = w.computeFingerprint()
        let fp2 = w.computeFingerprint()
        #expect(fp1 == fp2)
        #expect(fp1 != 0)
    }

    @Test("새 파일이 추가되면 fingerprint이 변한다")
    func detectsNewFile() throws {
        let root = Self.tmpRoot()
        try "first".write(
            to: root.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8)
        let w = KSAssetWatcher(root: root)
        let fp1 = w.computeFingerprint()
        try "second".write(
            to: root.appendingPathComponent("b.txt"),
            atomically: true, encoding: .utf8)
        let fp2 = w.computeFingerprint()
        #expect(fp1 != fp2)
    }

    @Test("파일 크기가 변하면 fingerprint이 변한다")
    func detectsSizeChange() throws {
        let root = Self.tmpRoot()
        let f = root.appendingPathComponent("a.txt")
        try "short".write(to: f, atomically: true, encoding: .utf8)
        let w = KSAssetWatcher(root: root)
        let fp1 = w.computeFingerprint()
        try "much longer content here".write(to: f, atomically: true, encoding: .utf8)
        let fp2 = w.computeFingerprint()
        #expect(fp1 != fp2)
    }

    @Test("run()이 변경 시 onChange를 호출하고 cancel에 응답한다")
    func runFiresOnChange() async throws {
        let root = Self.tmpRoot()
        try "v1".write(
            to: root.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8)
        let w = KSAssetWatcher(
            root: root,
            interval: .milliseconds(50),
            debounce: .milliseconds(10))

        let counter = ChangeCounter()
        let task = Task.detached {
            await w.run {
                await counter.bump()
            }
        }

        // 첫 폴링이 baseline을 잡을 때까지 기다린다.
        try await Task.sleep(for: .milliseconds(150))

        // 변경 트리거: mtime이 1초 단위로 끊기는 파일시스템도 있으므로
        // 다른 파일을 추가해 fingerprint 변동을 확실히 만든다.
        try "v2".write(
            to: root.appendingPathComponent("b.txt"),
            atomically: true, encoding: .utf8)

        // onChange 호출을 기다린다 (최대 2초).
        var observed = 0
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(50))
            observed = await counter.value
            if observed > 0 { break }
        }
        #expect(observed >= 1)

        task.cancel()
        try await Task.sleep(for: .milliseconds(150))
    }

    actor ChangeCounter {
        private(set) var value: Int = 0
        func bump() { value += 1 }
    }
}
