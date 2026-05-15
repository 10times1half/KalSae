import Foundation
import Testing

@testable import KalsaeCore

// MARK: - 레지스트리 ↔ 정책 평가기 통합

@Suite("KSCommandRegistry — capability gating")
struct KSCommandRegistryCapabilityTests {

    /// 호출 컨텍스트 헬퍼 — TaskLocal로 윈도우 라벨을 주입한다.
    private func dispatch(
        _ registry: KSCommandRegistry,
        command: String,
        windowLabel: String?,
        payload: Data = Data("{}".utf8)
    ) async -> Result<Data, KSError> {
        await KSInvocationContext.$windowLabel.withValue(windowLabel) {
            await registry.dispatch(name: command, args: payload)
        }
    }

    @Test("No evaluator installed → allowlist behavior unchanged")
    func backwardCompatible() async {
        let registry = KSCommandRegistry()
        await registry.register("hello") { _ in .success(Data("{}".utf8)) }
        let result = await dispatch(registry, command: "hello", windowLabel: "main")
        #expect((try? result.get()) != nil)
    }

    @Test("Evaluator denies → permissionDenied error")
    func evaluatorDeny() async {
        let registry = KSCommandRegistry()
        await registry.register("hello") { _ in .success(Data("{}".utf8)) }

        // capabilities는 있지만 어떤 권한도 'hello'를 허용하지 않음
        let cfg = KSCapabilitiesConfig(
            permissions: [
                KSPermission(identifier: "p", commandsAllow: ["something-else"])
            ],
            capabilities: [
                KSCapability(identifier: "c", permissions: ["p"])
            ])
        let ev = KSPolicyEvaluator(config: cfg, platform: "windows")
        await registry.setPolicyEvaluator(ev)

        let result = await dispatch(registry, command: "hello", windowLabel: "main")
        guard case .failure(let err) = result else {
            Issue.record("expected failure")
            return
        }
        #expect(err.code == .permissionDenied)
    }

    @Test("Evaluator allows → handler runs")
    func evaluatorAllow() async {
        let registry = KSCommandRegistry()
        await registry.register("hello") { _ in .success(Data("\"ok\"".utf8)) }

        let cfg = KSCapabilitiesConfig(
            permissions: [
                KSPermission(identifier: "p", commandsAllow: ["hello"])
            ],
            capabilities: [
                KSCapability(identifier: "c", permissions: ["p"])
            ])
        let ev = KSPolicyEvaluator(config: cfg, platform: "windows")
        await registry.setPolicyEvaluator(ev)

        let result = await dispatch(registry, command: "hello", windowLabel: "main")
        #expect((try? result.get()) == Data("\"ok\"".utf8))
    }

    @Test("Allowlist is enforced before evaluator (defense in depth)")
    func allowlistFirst() async {
        let registry = KSCommandRegistry()
        await registry.register("hello") { _ in .success(Data("{}".utf8)) }
        await registry.setAllowlist(["other-command"])

        // evaluator는 hello를 허용하지만 allowlist가 먼저 막는다
        let cfg = KSCapabilitiesConfig(
            permissions: [KSPermission(identifier: "p", commandsAllow: ["*"])],
            capabilities: [KSCapability(identifier: "c", permissions: ["p"])])
        let ev = KSPolicyEvaluator(config: cfg, platform: "windows")
        await registry.setPolicyEvaluator(ev)

        let result = await dispatch(registry, command: "hello", windowLabel: "main")
        guard case .failure(let err) = result else {
            Issue.record("expected failure")
            return
        }
        #expect(err.code == .commandNotAllowed)
    }

    @Test("Window label routing — settings cap blocks main window")
    func windowRouting() async {
        let registry = KSCommandRegistry()
        await registry.register("hello") { _ in .success(Data("{}".utf8)) }

        let cfg = KSCapabilitiesConfig(
            permissions: [KSPermission(identifier: "p", commandsAllow: ["hello"])],
            capabilities: [
                KSCapability(
                    identifier: "settings-only",
                    windows: ["settings"],
                    permissions: ["p"])
            ])
        let ev = KSPolicyEvaluator(config: cfg, platform: "windows")
        await registry.setPolicyEvaluator(ev)

        // main 윈도우는 매칭 안됨 → permissionDenied
        let blocked = await dispatch(registry, command: "hello", windowLabel: "main")
        if case .failure(let err) = blocked {
            #expect(err.code == .permissionDenied)
        } else {
            Issue.record("expected denial from main window")
        }

        // settings 윈도우는 통과
        let ok = await dispatch(registry, command: "hello", windowLabel: "settings")
        #expect((try? ok.get()) != nil)
    }
}
