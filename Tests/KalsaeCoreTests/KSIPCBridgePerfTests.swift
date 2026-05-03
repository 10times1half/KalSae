import Foundation
import Testing

@testable import KalsaeCore

/// IPC 핫패스 마이크로벤치마크.
///
/// 이 테스트는 절대 시간 단언을 하지 않는다 (CI 환경 변동성 때문).
/// `swift test --filter "KSIPCBridgePerf"` 로 로컬에서 실행한 뒤
/// 최적화 전후를 수동으로 비교한다.
/// Windows: Defender/Search Indexer 노이즈가 크므로 5회 median 권장.
@Suite("KSIPCBridgePerf")
@MainActor
struct KSIPCBridgePerfTests {

    // MARK: - Helpers

    private func makeBridge(registry: KSCommandRegistry) -> (KSIPCBridgeCore, [String]) {
        var posts: [String] = []
        let bridge = KSIPCBridgeCore(
            registry: registry,
            logLabel: "perf.test",
            post: { json throws(KSError) in posts.append(json) },
            hop: { block in Task { @MainActor in block() } }
        )
        return (bridge, posts)
    }

    private func measureNs(iterations: Int, block: @MainActor () async throws -> Void) async -> UInt64 {
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<iterations {
            try? await block()
        }
        let elapsed = clock.now - start
        let ns =
            UInt64(elapsed.components.seconds) * 1_000_000_000
            + UInt64(elapsed.components.attoseconds / 1_000_000_000)
        return ns / UInt64(iterations)
    }

    // MARK: - encodeForJS (동기, 직접 측정)

    @Test("encodeForJS — 작은 payload 1만회 (μs 기록용)")
    func encodeForJSSmallPayload() throws {
        let payload = Data(#"{"x":1}"#.utf8)
        let msg = KSIPCMessage(kind: .response, id: "42", payload: payload, isError: false)
        let iterations = 10_000

        let start = ContinuousClock.now
        for _ in 0..<iterations {
            _ = try KSIPCBridgeCore.encodeForJS(msg)
        }
        let elapsed = ContinuousClock.now - start
        let nsPerCall =
            (UInt64(elapsed.components.seconds) * 1_000_000_000
                + UInt64(elapsed.components.attoseconds / 1_000_000_000))
            / UInt64(iterations)
        print("[Perf] encodeForJS small  : \(nsPerCall) ns/call (\(iterations) iters)")
    }

    @Test("encodeForJS — 1KB payload 1만회")
    func encodeForJSMediumPayload() throws {
        let inner = String(repeating: #"{"key":"value","n":42},"#, count: 42)
        let payload = Data("[\(inner.dropLast())]".utf8)
        let msg = KSIPCMessage(kind: .response, id: "1", payload: payload, isError: false)
        let iterations = 10_000

        let start = ContinuousClock.now
        for _ in 0..<iterations {
            _ = try KSIPCBridgeCore.encodeForJS(msg)
        }
        let elapsed = ContinuousClock.now - start
        let nsPerCall =
            (UInt64(elapsed.components.seconds) * 1_000_000_000
                + UInt64(elapsed.components.attoseconds / 1_000_000_000))
            / UInt64(iterations)
        print("[Perf] encodeForJS 1KB    : \(nsPerCall) ns/call (\(iterations) iters)")
    }

    @Test("encodeForJS — 100KB payload 1천회")
    func encodeForJSLargePayload() throws {
        let inner = String(repeating: #"{"key":"value","n":42},"#, count: 4200)
        let payload = Data("[\(inner.dropLast())]".utf8)
        let msg = KSIPCMessage(kind: .response, id: "1", payload: payload, isError: false)
        let iterations = 1_000

        let start = ContinuousClock.now
        for _ in 0..<iterations {
            _ = try KSIPCBridgeCore.encodeForJS(msg)
        }
        let elapsed = ContinuousClock.now - start
        let nsPerCall =
            (UInt64(elapsed.components.seconds) * 1_000_000_000
                + UInt64(elapsed.components.attoseconds / 1_000_000_000))
            / UInt64(iterations)
        print("[Perf] encodeForJS 100KB  : \(nsPerCall) ns/call (\(iterations) iters)")
    }

    // MARK: - handleInbound 라운드트립

    @Test("handleInbound 라운드트립 — 작은 payload 1만회")
    func roundTripSmall() async throws {
        let registry = KSCommandRegistry()
        await registry.register("echo") { args in .success(args) }
        var posts: [String] = []
        let bridge = KSIPCBridgeCore(
            registry: registry,
            logLabel: "perf.small",
            post: { json throws(KSError) in posts.append(json) },
            hop: { block in Task { @MainActor in block() } }
        )
        let frame = #"{"kind":"invoke","id":"1","name":"echo","payload":{"x":1}}"#
        let iterations = 10_000

        let start = ContinuousClock.now
        for _ in 0..<iterations {
            bridge.handleInbound(frame)
        }
        // 모든 Task가 완료될 때까지 대기.
        try await waitUntil { posts.count >= iterations }
        let elapsed = ContinuousClock.now - start
        let nsPerCall =
            (UInt64(elapsed.components.seconds) * 1_000_000_000
                + UInt64(elapsed.components.attoseconds / 1_000_000_000))
            / UInt64(iterations)
        print("[Perf] roundTrip small    : \(nsPerCall) ns/call (\(iterations) iters, posts=\(posts.count))")
    }

    @Test("handleInbound 라운드트립 — 1KB payload 1천회")
    func roundTripMedium() async throws {
        let registry = KSCommandRegistry()
        await registry.register("echo") { args in .success(args) }
        var posts: [String] = []
        let bridge = KSIPCBridgeCore(
            registry: registry,
            logLabel: "perf.medium",
            post: { json throws(KSError) in posts.append(json) },
            hop: { block in Task { @MainActor in block() } }
        )
        let inner = String(repeating: #""k":"v","#, count: 60).dropLast()
        let frame = #"{"kind":"invoke","id":"1","name":"echo","payload":{"# + inner + "}}"
        let iterations = 1_000

        let start = ContinuousClock.now
        for _ in 0..<iterations {
            bridge.handleInbound(frame)
        }
        try await waitUntil { posts.count >= iterations }
        let elapsed = ContinuousClock.now - start
        let nsPerCall =
            (UInt64(elapsed.components.seconds) * 1_000_000_000
                + UInt64(elapsed.components.attoseconds / 1_000_000_000))
            / UInt64(iterations)
        print("[Perf] roundTrip 1KB      : \(nsPerCall) ns/call (\(iterations) iters)")
    }

    // MARK: - Private helpers

    private func waitUntil(
        timeoutMs: Int = 5000,
        _ predicate: @MainActor () -> Bool
    ) async throws {
        var elapsed = 0
        while !predicate() && elapsed < timeoutMs {
            try await Task.sleep(for: .milliseconds(10))
            elapsed += 10
        }
        #expect(predicate(), "wait predicate timed out after \(timeoutMs)ms")
    }

    @Test("emit 1만회 (응답 없음)")
    func emitOnly() throws {
        var posts: [String] = []
        let bridge = KSIPCBridgeCore(
            registry: KSCommandRegistry(),
            logLabel: "perf.emit",
            post: { json throws(KSError) in posts.append(json) },
            hop: { block in Task { @MainActor in block() } }
        )
        let iterations = 10_000

        let start = ContinuousClock.now
        for i in 0..<iterations {
            try bridge.emit(event: "tick", payload: ["n": i])
        }
        let elapsed = ContinuousClock.now - start
        let nsPerCall =
            (UInt64(elapsed.components.seconds) * 1_000_000_000
                + UInt64(elapsed.components.attoseconds / 1_000_000_000))
            / UInt64(iterations)
        print("[Perf] emit               : \(nsPerCall) ns/call (\(iterations) iters, posts=\(posts.count))")
    }
}
