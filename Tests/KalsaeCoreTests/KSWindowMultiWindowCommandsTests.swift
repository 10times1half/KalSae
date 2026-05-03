import Foundation
import Testing

@testable import KalsaeCore

/// `__ks.window.list` / `current` / `emit` 의 IPC 경로를 검증한다.
///
/// `create` 는 stub backend 가 throw 하므로 별도 통합 테스트 영역으로 미룬다.
/// `StubWindowBackend` 는 [KSWindowResolverTests.swift](KSWindowResolverTests.swift)
/// 에 정의된 것을 그대로 재사용한다 (같은 테스트 모듈 internal).
@Suite("Multi-window IPC commands", .serialized)
@MainActor
struct KSWindowMultiWindowCommandsTests {

    // ── 헬퍼 ────────────────────────────────────────────────

    /// `__ks.window.list` / `current` / `emit` 핸들러가 등록된 registry 와
    /// stub backend 를 반환한다.
    private func makeRegistry(
        seedLabels: [String]
    ) async -> (KSCommandRegistry, StubWindowBackend) {
        let backend = StubWindowBackend()
        for label in seedLabels {
            await backend.seed(KSWindowHandle(label: label, rawValue: UInt64(label.count)))
        }
        let registry = KSCommandRegistry()
        let resolver = WindowResolver(windows: backend, mainWindow: { nil })
        await KSBuiltinCommands.registerWindowCommands(
            into: registry, windows: backend, resolver: resolver)
        return (registry, backend)
    }

    /// `__KS_.invoke(name, args)` 를 직접 디스패치한 결과를 디코딩해 반환한다.
    private func dispatch<Out: Decodable>(
        _ registry: KSCommandRegistry,
        _ name: String,
        args: Data = Data("{}".utf8),
        as: Out.Type
    ) async throws -> Out {
        let result = await registry.dispatch(name: name, args: args)
        switch result {
        case .success(let data):
            return try JSONDecoder().decode(Out.self, from: data)
        case .failure(let error):
            throw error
        }
    }

    private struct LabelDTO: Decodable { let label: String }

    // ── __ks.window.list ───────────────────────────────────

    @Test("__ks.window.list returns all registered window labels")
    func listReturnsAllLabels() async throws {
        let (registry, _) = await makeRegistry(seedLabels: ["main", "overlay", "tools"])
        let labels = try await dispatch(
            registry, "__ks.window.list", as: [LabelDTO].self
        ).map(\.label)
        #expect(Set(labels) == ["main", "overlay", "tools"])
    }

    @Test("__ks.window.list returns empty array when no windows registered")
    func listEmpty() async throws {
        let (registry, _) = await makeRegistry(seedLabels: [])
        let labels = try await dispatch(
            registry, "__ks.window.list", as: [LabelDTO].self)
        #expect(labels.isEmpty)
    }

    // ── __ks.window.current ────────────────────────────────

    @Test("__ks.window.current returns the TaskLocal window label")
    func currentReturnsTaskLocalLabel() async throws {
        let (registry, _) = await makeRegistry(seedLabels: ["main", "overlay"])

        let dto: LabelDTO = try await KSInvocationContext.$windowLabel
            .withValue("overlay") {
                try await dispatch(registry, "__ks.window.current", as: LabelDTO.self)
            }
        #expect(dto.label == "overlay")
    }

    @Test("__ks.window.current throws invalidArgument when no TaskLocal context")
    func currentThrowsWithoutContext() async throws {
        let (registry, _) = await makeRegistry(seedLabels: ["main"])

        let result = await registry.dispatch(
            name: "__ks.window.current", args: Data("{}".utf8))
        switch result {
        case .success:
            Issue.record("expected failure but got success")
        case .failure(let error):
            #expect(error.code == .invalidArgument)
        }
    }

    // ── __ks.window.emit ───────────────────────────────────

    @Test("__ks.window.emit with target only invokes that sink")
    func emitTargeted() async throws {
        let (registry, _) = await makeRegistry(seedLabels: [])
        let recA = ReceivedRecorder()
        let recB = ReceivedRecorder()

        // EmitHub 에 두 개의 라벨 등록.
        let hub = KSWindowEmitHub.shared
        hub.register(label: "a") { event, _ throws(KSError) in recA.append(event) }
        hub.register(label: "b") { event, _ throws(KSError) in recB.append(event) }
        defer {
            hub.unregister(label: "a")
            hub.unregister(label: "b")
        }

        // payload `{ event:"ping", payload:{}, target:"b" }`
        let argsJSON = #"{"event":"ping","payload":{"x":1},"target":"b"}"#
        let result = await registry.dispatch(
            name: "__ks.window.emit", args: Data(argsJSON.utf8))
        if case .failure(let e) = result {
            Issue.record("emit dispatch failed: \(e)")
        }

        #expect(recA.events.isEmpty)
        #expect(recB.events == ["ping"])
    }

    @Test("__ks.window.emit with target=null broadcasts to all sinks")
    func emitBroadcast() async throws {
        let (registry, _) = await makeRegistry(seedLabels: [])
        let recA = ReceivedRecorder()
        let recB = ReceivedRecorder()

        let hub = KSWindowEmitHub.shared
        hub.register(label: "a") { event, _ throws(KSError) in recA.append(event) }
        hub.register(label: "b") { event, _ throws(KSError) in recB.append(event) }
        defer {
            hub.unregister(label: "a")
            hub.unregister(label: "b")
        }

        let argsJSON = #"{"event":"update","payload":{"x":1},"target":null}"#
        let result = await registry.dispatch(
            name: "__ks.window.emit", args: Data(argsJSON.utf8))
        if case .failure(let e) = result {
            Issue.record("emit dispatch failed: \(e)")
        }

        #expect(recA.events == ["update"])
        #expect(recB.events == ["update"])
    }
}

/// MainActor-isolated 테스트에서 사용하는 단순 이벤트 수집기.
@MainActor
private final class ReceivedRecorder {
    var events: [String] = []
    func append(_ event: String) { events.append(event) }
}
