import Testing
import Foundation
@testable import KalsaeCore

// MARK: - Registry concurrency & throughput
//
// Phase 9 측정 슈트. baseline을 못 박아 둠으로써 추후 최적화의 효과를
// 가시화하고, 동시 dispatch 정합성 회귀를 막는다.

@Suite("KSCommandRegistry — concurrency contract")
struct KSCommandRegistryConcurrencyTests {

    /// 1k 동시 dispatch가 모두 성공하고 결과가 정확하다.
    @Test("Concurrent dispatch returns correct results")
    func concurrentDispatch() async throws {
        let registry = KSCommandRegistry()
        await registry.register("echo") { data in
            return .success(data)
        }

        let payloads: [Data] = (0..<1000).map { i in
            Data("\(i)".utf8)
        }

        await withTaskGroup(of: (Int, Data).self) { group in
            for (i, p) in payloads.enumerated() {
                group.addTask {
                    let r = await registry.dispatch(name: "echo", args: p)
                    switch r {
                    case .success(let d): return (i, d)
                    case .failure: return (i, Data())
                    }
                }
            }
            var seen = Set<Int>()
            for await (i, data) in group {
                seen.insert(i)
                #expect(data == payloads[i],
                    "echo handler must return its argument unchanged")
            }
            #expect(seen.count == 1000)
        }
    }

    /// `setAllowlist` 도중 dispatch가 일관성 있게 적용/거부된다.
    @Test("Allowlist tightening is observable to subsequent dispatches")
    func allowlistRace() async throws {
        let registry = KSCommandRegistry()
        await registry.register("a") { _ in .success(Data()) }
        await registry.register("b") { _ in .success(Data()) }

        // Tighten to {"a"} only. After this completes, b must fail.
        await registry.setAllowlist(["a"])

        let okA = await registry.dispatch(name: "a", args: Data())
        let denyB = await registry.dispatch(name: "b", args: Data())

        switch okA {
        case .success: break
        case .failure(let e): Issue.record("a should pass: \(e)")
        }
        switch denyB {
        case .success: Issue.record("b should be denied")
        case .failure(let e): #expect(e.code == .commandNotAllowed)
        }
    }

    /// 미등록 이름은 `commandNotFound`.
    @Test("Unknown command returns commandNotFound")
    func unknownCommand() async {
        let registry = KSCommandRegistry()
        let r = await registry.dispatch(name: "nope", args: Data())
        switch r {
        case .success: Issue.record("must fail")
        case .failure(let e): #expect(e.code == .commandNotFound)
        }
    }

    /// 측정 마이크로벤치: 단일 핸들러에 1k 순차 dispatch.
    /// 결과를 게이트하지 않고 baseline만 기록한다 — 회귀가 의심되면
    /// 이 수치를 비교 기준으로 사용한다.
    @Test("Throughput baseline (informational)")
    func throughputBaseline() async {
        let registry = KSCommandRegistry()
        await registry.register("noop") { _ in .success(Data()) }

        let iterations = 1_000
        let start = DispatchTime.now()
        for _ in 0..<iterations {
            _ = await registry.dispatch(name: "noop", args: Data())
        }
        let elapsedNs = DispatchTime.now().uptimeNanoseconds
                      - start.uptimeNanoseconds
        let perCall = elapsedNs / UInt64(iterations)

        // 정보용 — 실패 게이트 없음. 명백히 무너진 경우에만 fail.
        #expect(perCall < 1_000_000,
            "noop dispatch must stay under 1 ms (got \(perCall) ns)")
    }
}
