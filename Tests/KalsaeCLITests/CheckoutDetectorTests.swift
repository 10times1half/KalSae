import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSKalsaeCheckoutDetector")
struct CheckoutDetectorTests {

    private func uniqueDir(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-detect-\(UUID().uuidString)-\(suffix)")
    }

    private func writeText(_ s: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try s.write(to: url, atomically: false, encoding: .utf8)
    }

    /// `kalsae` 가 체크아웃의 `.build/` 안에 있고 워크스페이스 마커
    /// (`Package.swift` + `Sources/Kalsae/Kalsae.swift`) 가 모두 있으면 root 검출.
    @Test("detects checkout root when exe lives under .build/ with required markers")
    func detectsCheckoutRoot() throws {
        let fm = FileManager.default
        let root = uniqueDir("checkout").standardizedFileURL
        defer { try? fm.removeItem(at: root) }

        try writeText("// dummy", to: root.appendingPathComponent("Package.swift"))
        try writeText(
            "// dummy",
            to: root.appendingPathComponent("Sources/Kalsae/Kalsae.swift"))
        let exe =
            root
            .appendingPathComponent(".build/x86_64-windows-msvc/release/kalsae.exe")
        try writeText("MZ", to: exe)

        let result = KSKalsaeCheckoutDetector.find(
            executableURL: exe,
            environment: [:],
            fm: fm)
        #expect(result?.standardizedFileURL.path == root.path)
    }

    /// `Sources/Kalsae/Kalsae.swift` 마커가 없으면 nil — 임의 SwiftPM 프로젝트가
    /// 잘못 검출되지 않아야 한다.
    @Test("returns nil for non-Kalsae checkouts")
    func ignoresUnrelatedCheckouts() throws {
        let fm = FileManager.default
        let root = uniqueDir("unrelated").standardizedFileURL
        defer { try? fm.removeItem(at: root) }

        try writeText("// dummy", to: root.appendingPathComponent("Package.swift"))
        // Sources/Kalsae/Kalsae.swift 누락
        let exe = root.appendingPathComponent(".build/release/kalsae.exe")
        try writeText("MZ", to: exe)

        let result = KSKalsaeCheckoutDetector.find(
            executableURL: exe,
            environment: [:],
            fm: fm)
        #expect(result == nil)
    }

    /// `KALSAE_DISABLE_AUTODETECT_PATH=1` opt-out 은 강제로 nil.
    @Test("opt-out env var disables detection")
    func optOutEnvironment() throws {
        let fm = FileManager.default
        let root = uniqueDir("optout").standardizedFileURL
        defer { try? fm.removeItem(at: root) }

        try writeText("// dummy", to: root.appendingPathComponent("Package.swift"))
        try writeText(
            "// dummy",
            to: root.appendingPathComponent("Sources/Kalsae/Kalsae.swift"))
        let exe = root.appendingPathComponent(".build/release/kalsae.exe")
        try writeText("MZ", to: exe)

        let result = KSKalsaeCheckoutDetector.find(
            executableURL: exe,
            environment: ["KALSAE_DISABLE_AUTODETECT_PATH": "1"],
            fm: fm)
        #expect(result == nil)
    }

    /// exe 가 `.build/` 트리 밖에 있으면 nil — 설치된 글로벌 `kalsae` 케이스.
    @Test("returns nil when exe is outside any .build/ tree")
    func ignoresGloballyInstalledExe() throws {
        let fm = FileManager.default
        let root = uniqueDir("global").standardizedFileURL
        defer { try? fm.removeItem(at: root) }

        try writeText("// dummy", to: root.appendingPathComponent("Package.swift"))
        try writeText(
            "// dummy",
            to: root.appendingPathComponent("Sources/Kalsae/Kalsae.swift"))
        // exe 는 별도 위치 (e.g. Program Files).
        let exe = uniqueDir("install").appendingPathComponent("bin/kalsae.exe")
        try writeText("MZ", to: exe)
        defer { try? fm.removeItem(at: exe.deletingLastPathComponent().deletingLastPathComponent()) }

        let result = KSKalsaeCheckoutDetector.find(
            executableURL: exe,
            environment: [:],
            fm: fm)
        #expect(result == nil)
    }
}
