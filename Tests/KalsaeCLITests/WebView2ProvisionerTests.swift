import Foundation
import Testing

@testable import KalsaeCLICore

/// `KSWebView2Provisioner.stageLoaderDLL` 의 known-triple 직접 검사 동작
/// (RFC-002 §3.3) 회귀 테스트. Windows 외 플랫폼에서는 함수 자체가 no-op
/// 이므로 의미 있는 검증을 할 수 없어 `#if os(Windows)` 로 게이트한다.
@Suite("KSWebView2Provisioner — stageLoaderDLL")
struct WebView2ProvisionerStageTests {
    private func uniqueDir(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-wv2prov-\(UUID().uuidString)-\(suffix)")
    }

    #if os(Windows)
        /// `.build/` 안에 known triple 디렉터리와 bogus 디렉터리를 함께 두고
        /// `stageLoaderDLL` 을 호출하면 known triple 에만 DLL 이 staging 되고
        /// bogus 디렉터리는 건드리지 않아야 한다. 이전 구현은 `.build/` 의
        /// 모든 자식 디렉터리를 enumerator 로 순회했기 때문에 bogus
        /// 디렉터리에도 fileExists 호출이 발생했다. 새 구현은 known triple
        /// 만 직접 검사한다.
        @Test("stageLoaderDLL stages known Windows triples only")
        func knownTriplesOnly() throws {
            let fm = FileManager.default
            let cwd = uniqueDir("known-triple")
            try fm.createDirectory(at: cwd, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: cwd) }

            // 가짜 Kalsae 체크아웃 + WebView2Loader.dll 소스
            let loaderSrc =
                cwd
                .appendingPathComponent("Sources")
                .appendingPathComponent("CKalsaeWV2")
                .appendingPathComponent("Vendor")
                .appendingPathComponent("WebView2")
                .appendingPathComponent("runtimes")
                .appendingPathComponent("win-x64")
                .appendingPathComponent("native")
                .appendingPathComponent("WebView2Loader.dll")
            try fm.createDirectory(
                at: loaderSrc.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try "loader-bytes".write(
                to: loaderSrc, atomically: false, encoding: .utf8)
            // 마커 디렉터리 (`Sources/CKalsaeWV2/include`) — discoverKalsaeRoots 가 인식.
            try fm.createDirectory(
                at:
                    cwd
                    .appendingPathComponent("Sources")
                    .appendingPathComponent("CKalsaeWV2")
                    .appendingPathComponent("include"),
                withIntermediateDirectories: true)

            // .build/ 안에 known triple 한 개 + bogus 디렉터리 한 개.
            let configuration = "release"
            let buildDir = cwd.appendingPathComponent(".build")
            let knownTriple =
                buildDir
                .appendingPathComponent("x86_64-unknown-windows-msvc")
                .appendingPathComponent(configuration)
            let bogus =
                buildDir
                .appendingPathComponent("junk-vendor-tooling")
                .appendingPathComponent(configuration)
            try fm.createDirectory(at: knownTriple, withIntermediateDirectories: true)
            try fm.createDirectory(at: bogus, withIntermediateDirectories: true)

            try KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: configuration)

            #expect(
                fm.fileExists(
                    atPath: knownTriple.appendingPathComponent("WebView2Loader.dll").path),
                "known triple 디렉터리에는 DLL 이 staging 되어야 한다")
            #expect(
                !fm.fileExists(
                    atPath: bogus.appendingPathComponent("WebView2Loader.dll").path),
                "bogus 디렉터리에는 DLL 이 staging 되지 않아야 한다")
        }
    #endif

    /// 함수가 다른 플랫폼에서 no-op 임을 적어도 호출 가능한지 확인하는
    /// smoke test (Windows 외에서 컴파일/실행 시 빈 통과). Windows 에서는
    /// 소스 DLL 이 없으면 throw 하도록 강화됐으므로 이 테스트는 Windows
    /// 외 플랫폼에서만 의미가 있다.
    #if !os(Windows)
        @Test("stageLoaderDLL is a no-op on non-Windows hosts")
        func noOpOnNonWindows() throws {
            let cwd = uniqueDir("noop")
            // 비-Windows 에서 호출해도 throw 하지 않아야 함.
            try KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: "debug")
        }
    #endif
}
