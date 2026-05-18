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
