import Foundation
import Testing

@testable import Kalsae

/// `KSApp.autoResolveResourceRoot(frontendDist:)` 단위 테스트.
///
/// axis feedback Proposal #2 — `boot(config:)` 가 `resourceRoot` 를 받지 못했을
/// 때 실행 파일 옆 `frontendDist` 디렉터리로 자동 해석되어야 한다는 계약을
/// 검증한다. 디렉터리가 존재하지 않거나 `frontendDist` 가 빈 문자열이면
/// `nil` 을 돌려줘서 호출자가 fallback 으로 떨어지도록 한다.
@Suite("KSApp — autoResolveResourceRoot")
@MainActor
struct KSAppAutoResolveResourceRootTests {
    /// 임시 디렉터리에 `frontendDist` 후보를 만들어 두면 그 URL 이 그대로
    /// 돌아오는지 — 단, 실행 파일 옆이 아니므로 실제 동작과는 다르게
    /// 항상 `nil`. 즉 *실제* 자동 해석은 실행 파일 위치에 의존하므로
    /// 유닛 테스트에서는 "negative case 만 확정적으로" 검증 가능하다.

    @Test("빈 frontendDist 는 nil 반환")
    func emptyFrontendDistReturnsNil() {
        let result = KSApp.autoResolveResourceRoot(frontendDist: "")
        #expect(result == nil)
    }

    @Test("존재하지 않는 디렉터리는 nil 반환")
    func nonexistentDirectoryReturnsNil() {
        // 실행 파일 위치는 테스트 러너의 .xctest/.build 경로이며,
        // 거기에 `__kalsae_test_does_not_exist__` 디렉터리가 있을 리 없다.
        let result = KSApp.autoResolveResourceRoot(
            frontendDist: "__kalsae_test_does_not_exist__")
        #expect(result == nil)
    }

    @Test("실행 파일 옆에 디렉터리를 만들면 그 URL 반환")
    func directoryNextToExecutableReturnsURL() throws {
        let exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent()
        // 고유한 이름으로 충돌 회피
        let name = "__ksapp_autoresolve_test_\(UUID().uuidString)__"
        let candidate = exeDir.appendingPathComponent(name)
        let fm = FileManager.default
        try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: candidate) }

        let result = KSApp.autoResolveResourceRoot(frontendDist: name)
        #expect(result != nil)
        // URL.standardizedFileURL 은 디렉터리에 trailing-slash 를 붙이는데,
        // 결과 URL 과 후보 URL 의 슬래시 처리가 플랫폼/타이밍에 따라 달라질 수
        // 있어 `.path` 로 정규화해서 비교한다.
        #expect(result?.path == candidate.path)
    }

    @Test("파일은 디렉터리가 아니므로 nil 반환")
    func plainFileReturnsNil() throws {
        let exeDir = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent()
        let name = "__ksapp_autoresolve_file_\(UUID().uuidString)__"
        let candidate = exeDir.appendingPathComponent(name)
        let fm = FileManager.default
        try Data("hello".utf8).write(to: candidate)
        defer { try? fm.removeItem(at: candidate) }

        let result = KSApp.autoResolveResourceRoot(frontendDist: name)
        #expect(result == nil)
    }
}
