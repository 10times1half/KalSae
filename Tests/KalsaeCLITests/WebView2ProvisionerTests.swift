import Foundation
import Testing

@testable import KalsaeCLICore

/// `KSWebView2Provisioner.stageLoaderDLL` 의 staging 동작 회귀 테스트.
/// Windows 외 플랫폼에서는 함수 자체가 no-op 이므로 의미 있는 검증을
/// 할 수 없어 Windows 케이스는 `#if os(Windows)` 로 게이트한다.
@Suite("KSWebView2Provisioner — stageLoaderDLL")
struct WebView2ProvisionerStageTests {
    private func uniqueDir(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-wv2prov-\(UUID().uuidString)-\(suffix)")
    }

    #if os(Windows)
        /// 가짜 Kalsae 체크아웃을 만들고 known triple 디렉터리 한 개 +
        /// bogus 디렉터리 한 개를 둔 뒤 `stageLoaderDLL` 을 호출한다.
        /// host triple 에는 DLL 이 staging 되고 bogus 디렉터리는 절대로
        /// 건드리지 않아야 한다. (RFC-002 §3.3 — `.build/` 전체 순회 금지)
        @Test("stageLoaderDLL stages known Windows triples only")
        func knownTriplesOnly() throws {
            let fm = FileManager.default
            let cwd = uniqueDir("known-triple")
            try fm.createDirectory(at: cwd, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: cwd) }

            try makeFakeCheckout(at: cwd)

            // host triple 결정 — 새 구현은 컴파일타임 arch 매크로로 host
            // triple 을 선택하므로 테스트도 같은 매크로를 따라야 한다.
            #if arch(arm64)
                let hostTriple = "aarch64-unknown-windows-msvc"
            #else
                let hostTriple = "x86_64-unknown-windows-msvc"
            #endif

            let configuration = "release"
            let buildDir = cwd.appendingPathComponent(".build")
            let hostDest =
                buildDir
                .appendingPathComponent(hostTriple)
                .appendingPathComponent(configuration)
            let bogus =
                buildDir
                .appendingPathComponent("junk-vendor-tooling")
                .appendingPathComponent(configuration)
            try fm.createDirectory(at: bogus, withIntermediateDirectories: true)

            try KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: configuration)

            #expect(
                fm.fileExists(
                    atPath: hostDest.appendingPathComponent("WebView2Loader.dll").path),
                "host triple 디렉터리에는 DLL 이 staging 되어야 한다")
            #expect(
                !fm.fileExists(
                    atPath: bogus.appendingPathComponent("WebView2Loader.dll").path),
                "bogus 디렉터리에는 DLL 이 staging 되지 않아야 한다")
        }

        /// `.build/<configuration>/` 가 사전에 존재하지 않으면 `stageLoaderDLL`
        /// 은 그 경로를 *새로 만들지 말아야* 한다. SwiftPM 이 빌드 후 같은
        /// 위치에 symlink 를 만들 영역을 미리 실 디렉터리로 점유해버리면
        /// EXE 와 DLL 이 서로 다른 디렉터리에 위치해 `LoadLibraryW` 가
        /// `0x8007007E (ERROR_MOD_NOT_FOUND)` 로 실패한다.
        @Test("stageLoaderDLL does not create .build/<configuration>/ when it is absent")
        func doesNotCreateLegacyDestWhenAbsent() throws {
            let fm = FileManager.default
            let cwd = uniqueDir("no-legacy")
            try fm.createDirectory(at: cwd, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: cwd) }

            try makeFakeCheckout(at: cwd)

            let configuration = "debug"
            let legacyDest =
                cwd
                .appendingPathComponent(".build")
                .appendingPathComponent(configuration)
            #expect(
                !fm.fileExists(atPath: legacyDest.path),
                "사전 조건: legacy 경로가 비어 있어야 함")

            try KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: configuration)

            #expect(
                !fm.fileExists(atPath: legacyDest.path),
                "stageLoaderDLL 은 .build/<configuration>/ 을 새로 만들지 말아야 한다 (SwiftPM 의 symlink 생성 영역).")
        }

        /// `.build/<configuration>/` 가 *사전에* 실제 디렉터리로 존재하면
        /// (예: 이전 빌드의 잔재) `stageLoaderDLL` 은 그곳에도 DLL 을
        /// staging 해야 한다. 이미 존재하는 영역은 안전하게 사용 가능.
        @Test("stageLoaderDLL stages into pre-existing .build/<configuration>/")
        func stagesIntoExistingLegacyDest() throws {
            let fm = FileManager.default
            let cwd = uniqueDir("with-legacy")
            try fm.createDirectory(at: cwd, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: cwd) }

            try makeFakeCheckout(at: cwd)

            let configuration = "release"
            let legacyDest =
                cwd
                .appendingPathComponent(".build")
                .appendingPathComponent(configuration)
            try fm.createDirectory(at: legacyDest, withIntermediateDirectories: true)

            try KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: configuration)

            #expect(
                fm.fileExists(
                    atPath: legacyDest.appendingPathComponent("WebView2Loader.dll").path),
                "사전에 존재하던 legacy 디렉터리에도 DLL 이 staging 되어야 한다")
        }

        // MARK: - Fixtures

        /// 가짜 Kalsae 체크아웃을 `cwd` 에 만든다:
        /// - `Sources/CKalsaeWV2/include/` (`discoverKalsaeRoots` 마커)
        /// - `Sources/CKalsaeWV2/Vendor/WebView2/runtimes/win-x64/native/WebView2Loader.dll`
        ///   (stage 의 소스 파일)
        private func makeFakeCheckout(at cwd: URL) throws {
            let fm = FileManager.default
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
            try fm.createDirectory(
                at:
                    cwd
                    .appendingPathComponent("Sources")
                    .appendingPathComponent("CKalsaeWV2")
                    .appendingPathComponent("include"),
                withIntermediateDirectories: true)
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
