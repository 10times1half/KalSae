import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSWindowsRuntimeStager — whitelist")
struct WindowsRuntimeStagerWhitelistTests {

    @Test("Whitelists Swift runtime DLLs")
    func whitelistsSwiftRuntime() {
        #expect(KSWindowsRuntimeStager.isWhitelisted("swift_concurrency.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("swiftcore.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("swiftfoundation.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("foundation.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("_foundation.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("dispatch.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("blocksruntime.dll"))
    }

    @Test("Whitelists ICU and VC redist")
    func whitelistsICUAndVC() {
        #expect(KSWindowsRuntimeStager.isWhitelisted("icudt74.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("icuuc74.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("vcruntime140.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("vcruntime140_1.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("msvcp140.dll"))
        #expect(KSWindowsRuntimeStager.isWhitelisted("concrt140.dll"))
    }

    @Test("Rejects system DLLs")
    func rejectsSystem() {
        #expect(!KSWindowsRuntimeStager.isWhitelisted("kernel32.dll"))
        #expect(!KSWindowsRuntimeStager.isWhitelisted("user32.dll"))
        #expect(!KSWindowsRuntimeStager.isWhitelisted("ntdll.dll"))
        #expect(!KSWindowsRuntimeStager.isWhitelisted("ole32.dll"))
        #expect(!KSWindowsRuntimeStager.isWhitelisted("webview2loader.dll"))
    }

    #if os(Windows)
        /// 비-Windows 호스트에서는 no-op 으로 0 을 반환해야 한다.
        /// Windows 에서는 실제 staging 동작은 빌드 산출물이 있을 때만 의미가 있으므로
        /// 여기서는 잘못된 입력이 throw 하지 않고 0 또는 양수를 돌려주는지만 확인.
        @Test("stageBuildOutputs returns 0 when build dir does not exist")
        func stageBuildOutputsMissingDir() throws {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("ks-stager-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let count = try KSWindowsRuntimeStager.stageBuildOutputs(
                cwd: tmp, configuration: "debug")
            #expect(count == 0)
        }
    #else
        @Test("Non-Windows host returns 0")
        func noOpOnNonWindows() throws {
            let dummy = URL(fileURLWithPath: "/tmp/does-not-exist.exe")
            let count = try KSWindowsRuntimeStager.stage(executable: dummy)
            #expect(count == 0)
        }
    #endif
}

#if os(Windows)
    /// `discoverSearchDirs()` 가 swift.org 공식 Windows installer 의
    /// `<install>\Toolchains\<ver>\usr\bin\swift.exe` ↔
    /// `<install>\Runtimes\<ver>\usr\bin\swiftCore.dll` 레이아웃을 잡아내는지,
    /// PATH 폴백이 동작하는지를 검증한다. 가짜 toolchain 트리를 tmp 에 만들고
    /// `PATH` 환경변수를 일시적으로 덮어쓴다.
    @Suite("KSWindowsRuntimeStager — discoverSearchDirs (Windows)")
    struct WindowsRuntimeStagerDiscoveryTests {

        @Test("4단계 위 Runtimes/<ver>/usr/bin 을 잡는다 (swift.org 공식 레이아웃)")
        func walksUpFourLevelsToRuntimesSibling() throws {
            let fm = FileManager.default
            let root = fm.temporaryDirectory
                .appendingPathComponent("ks-stager-disc-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: root) }

            // <install>\Toolchains\1.0\usr\bin\swift.exe  ← PATH 의 swiftDir
            // <install>\Runtimes\1.0\usr\bin\swiftCore.dll ← 기대 매칭 대상
            let swiftBin = root.appendingPathComponent("Toolchains/1.0/usr/bin")
            let runtimesBin = root.appendingPathComponent("Runtimes/1.0/usr/bin")
            try fm.createDirectory(at: swiftBin, withIntermediateDirectories: true)
            try fm.createDirectory(at: runtimesBin, withIntermediateDirectories: true)
            // 빈 파일이면 충분 — discoverSearchDirs 는 디렉터리 존재 여부만 본다.
            #expect(fm.createFile(atPath: swiftBin.appendingPathComponent("swift.exe").path, contents: Data()))
            #expect(
                fm.createFile(
                    atPath: runtimesBin.appendingPathComponent("swiftCore.dll").path, contents: Data()))

            let env = ["PATH": swiftBin.path]
            let dirs = KSWindowsRuntimeStager.discoverSearchDirs(fm: fm, env: env)

            let paths = dirs.map { $0.path.lowercased() }
            #expect(paths.contains(swiftBin.path.lowercased()))
            #expect(paths.contains(runtimesBin.path.lowercased()))
        }

        @Test("swift.exe 와 무관한 PATH 엔트리에 있는 swiftCore.dll 도 PATH 폴백으로 잡힌다")
        func pathFallbackPicksUpOrphanRuntimeDir() throws {
            let fm = FileManager.default
            let root = fm.temporaryDirectory
                .appendingPathComponent("ks-stager-path-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: root) }

            // swift.exe 는 A 디렉터리에, swiftCore.dll 은 B (완전 별개) 디렉터리에.
            let swiftBin = root.appendingPathComponent("A/swift-bin")
            let orphanRuntime = root.appendingPathComponent("B/runtime-bin")
            try fm.createDirectory(at: swiftBin, withIntermediateDirectories: true)
            try fm.createDirectory(at: orphanRuntime, withIntermediateDirectories: true)
            #expect(fm.createFile(atPath: swiftBin.appendingPathComponent("swift.exe").path, contents: Data()))
            #expect(
                fm.createFile(
                    atPath: orphanRuntime.appendingPathComponent("swiftCore.dll").path,
                    contents: Data()))

            // 두 디렉터리 모두 PATH 에 등록.
            let env = ["PATH": "\(swiftBin.path);\(orphanRuntime.path)"]
            let dirs = KSWindowsRuntimeStager.discoverSearchDirs(fm: fm, env: env)

            let paths = dirs.map { $0.path.lowercased() }
            #expect(paths.contains(orphanRuntime.path.lowercased()))
        }
    }
#endif
