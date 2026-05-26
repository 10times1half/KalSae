import Foundation
import Testing

@testable import KalsaeCore

// MARK: - 0.4.0 default-deny allowlist & registerInternal bypass
//
// Regression suite for RFC-000 P1.1 (D1-D4 decisions).
//   - `setAllowlist(nil)`  -> allow-all for user commands
//   - `setAllowlist([])`   -> deny-all for user commands
//   - `setAllowlist(["x"])` -> only "x" passes
//   - `registerInternal(...)` registered commands always pass regardless of allowlist

@Suite("KSCommandRegistry — allowlist semantics")
struct KSCommandRegistryAllowlistTests {

    private func makeRegistry() async -> KSCommandRegistry {
        let registry = KSCommandRegistry()
        await registry.register("user.foo") { _ in .success(Data("foo".utf8)) }
        await registry.register("user.bar") { _ in .success(Data("bar".utf8)) }
        await registry.registerInternal("__ks.builtin") { _ in
            .success(Data("builtin".utf8))
        }
        return registry
    }

    @Test("nil allowlist (allow-all): user commands dispatch")
    func nilAllowlistAllowsUserCommands() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist(nil)
        let r = await registry.dispatch(name: "user.foo", args: Data())
        if case .failure(let e) = r {
            Issue.record("expected success, got \(e)")
        }
    }

    @Test("Empty allowlist (deny-all): user commands rejected")
    func emptyAllowlistBlocksUserCommands() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist([])
        let r = await registry.dispatch(name: "user.foo", args: Data())
        guard case .failure(let e) = r else {
            Issue.record("expected commandNotAllowed, got success")
            return
        }
        #expect(e.code == .commandNotAllowed)
    }

    @Test("Empty allowlist still permits internal __ks.* commands")
    func emptyAllowlistPermitsInternal() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist([])
        let r = await registry.dispatch(name: "__ks.builtin", args: Data())
        if case .failure(let e) = r {
            Issue.record("internal command must bypass allowlist, got \(e)")
        }
    }

    @Test("Explicit whitelist: only listed user commands pass")
    func whitelistGatesUserCommands() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist(["user.foo"])
        let allowed = await registry.dispatch(name: "user.foo", args: Data())
        if case .failure(let e) = allowed {
            Issue.record("user.foo should be allowed, got \(e)")
        }
        let denied = await registry.dispatch(name: "user.bar", args: Data())
        guard case .failure(let e) = denied else {
            Issue.record("user.bar should be denied")
            return
        }
        #expect(e.code == .commandNotAllowed)
    }

    @Test("Explicit whitelist does not block internal commands")
    func whitelistDoesNotBlockInternal() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist(["user.foo"])
        let r = await registry.dispatch(name: "__ks.builtin", args: Data())
        if case .failure(let e) = r {
            Issue.record("internal command must bypass allowlist, got \(e)")
        }
    }

    @Test("unregister clears internal marker")
    func unregisterClearsInternal() async throws {
        let registry = KSCommandRegistry()
        await registry.registerInternal("__ks.tmp") { _ in .success(Data()) }
        await registry.unregister("__ks.tmp")
        // After unregister + plain re-register, the internal marker is gone,
        // so deny-all must block the same name.
        await registry.register("__ks.tmp") { _ in .success(Data()) }
        await registry.setAllowlist([])
        let r = await registry.dispatch(name: "__ks.tmp", args: Data())
        guard case .failure(let e) = r else {
            Issue.record("expected deny after re-register as user command")
            return
        }
        #expect(e.code == .commandNotAllowed)
    }
}

// MARK: - 0.4.3 glob pattern support (axis feedback Proposal #1)
//
// `commandAllowlist` 는 `KSPermission.matches` 와 동일한 글롭 문법을 지원한다:
//   - `"system.*"` -> "system.info" 매칭, "other" 불일치
//   - `"*"` -> 모두 매칭
//   - 리터럴 이름은 backward-compat (정확 일치만)

@Suite("KSCommandRegistry — allowlist glob")
struct KSCommandRegistryAllowlistGlobTests {

    private func makeRegistry() async -> KSCommandRegistry {
        let registry = KSCommandRegistry()
        await registry.register("system.info") { _ in .success(Data("info".utf8)) }
        await registry.register("system.shutdown") { _ in .success(Data("shutdown".utf8)) }
        await registry.register("llama.run") { _ in .success(Data("run".utf8)) }
        await registry.register("plain") { _ in .success(Data("plain".utf8)) }
        return registry
    }

    @Test("prefix glob 'system.*' matches all system commands")
    func prefixGlobMatches() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist(["system.*"])

        switch await registry.dispatch(name: "system.info", args: Data()) {
        case .success: break
        case .failure(let e):
            Issue.record("expected system.info to pass, got \(e)")
        }
        switch await registry.dispatch(name: "system.shutdown", args: Data()) {
        case .success: break
        case .failure(let e):
            Issue.record("expected system.shutdown to pass, got \(e)")
        }
    }

    @Test("prefix glob does not match other domains")
    func prefixGlobIsolation() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist(["system.*"])
        guard case .failure(let e) = await registry.dispatch(name: "llama.run", args: Data())
        else {
            Issue.record("expected llama.run to be denied by 'system.*'")
            return
        }
        #expect(e.code == .commandNotAllowed)
    }

    @Test("wildcard '*' matches everything")
    func wildcardMatchesAll() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist(["*"])
        for name in ["system.info", "llama.run", "plain"] {
            switch await registry.dispatch(name: name, args: Data()) {
            case .success: break
            case .failure(let e):
                Issue.record("expected '\(name)' to pass under '*', got \(e)")
            }
        }
    }

    @Test("literal names still match exactly (backward-compat)")
    func literalBackwardCompat() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist(["plain", "system.info"])
        switch await registry.dispatch(name: "plain", args: Data()) {
        case .success: break
        case .failure(let e):
            Issue.record("expected literal 'plain' to pass, got \(e)")
        }
        guard case .failure(let e) = await registry.dispatch(
            name: "system.shutdown", args: Data())
        else {
            Issue.record("expected non-listed literal to be denied")
            return
        }
        #expect(e.code == .commandNotAllowed)
    }

    @Test("mixed literal + glob")
    func mixedPatterns() async throws {
        let registry = await makeRegistry()
        await registry.setAllowlist(["plain", "system.*"])
        for name in ["plain", "system.info", "system.shutdown"] {
            switch await registry.dispatch(name: name, args: Data()) {
            case .success: break
            case .failure(let e):
                Issue.record("expected '\(name)' to pass, got \(e)")
            }
        }
        guard case .failure = await registry.dispatch(name: "llama.run", args: Data()) else {
            Issue.record("expected llama.run to be denied")
            return
        }
    }
}
