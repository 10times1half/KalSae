import Foundation
import Testing

@testable import KalsaeCore

// MARK: - 권한/Capability 평가 단위 테스트
//
// `KSPolicyEvaluator`의 평가 규칙(매칭, deny-우선, unknown-permission 등)을
// 격리해서 검증한다. `KSCommandRegistry`와의 통합 동작은 별도 슈트에서 검증.

@Suite("KSPolicyEvaluator — decision rules")
struct KSPolicyEvaluatorTests {

    private func evaluator(
        permissions: [KSPermission],
        capabilities: [KSCapability],
        platform: String = "windows"
    ) -> KSPolicyEvaluator {
        let cfg = KSCapabilitiesConfig(
            permissions: permissions, capabilities: capabilities)
        return KSPolicyEvaluator(config: cfg, platform: platform)
    }

    @Test("Empty capabilities → noMatchingCapability")
    func noCapabilities() {
        let ev = evaluator(permissions: [], capabilities: [])
        let d = ev.evaluate(command: "fs.readFile", windowLabel: "main")
        guard case .deny(reason: .noMatchingCapability) = d else {
            Issue.record("expected noMatchingCapability, got \(d)")
            return
        }
    }

    @Test("Single allow permission matches command")
    func simpleAllow() {
        let perm = KSPermission(
            identifier: "fs:read",
            commandsAllow: ["fs.readFile"])
        let cap = KSCapability(
            identifier: "main-cap",
            windows: ["main"],
            permissions: ["fs:read"])
        let ev = evaluator(permissions: [perm], capabilities: [cap])

        let d = ev.evaluate(command: "fs.readFile", windowLabel: "main")
        #expect(d == .allow(capability: "main-cap"))
    }

    @Test("Deny wins over allow within same capability")
    func denyOverAllow() {
        let allowAll = KSPermission(
            identifier: "fs:allow-all",
            commandsAllow: ["*"])
        let denyWrite = KSPermission(
            identifier: "fs:deny-write",
            commandsDeny: ["fs.writeFile"])
        let cap = KSCapability(
            identifier: "main",
            permissions: ["fs:allow-all", "fs:deny-write"])
        let ev = evaluator(
            permissions: [allowAll, denyWrite], capabilities: [cap])

        // read는 허용
        #expect(
            ev.evaluate(command: "fs.readFile", windowLabel: "main")
                == .allow(capability: "main"))
        // write는 거부
        let d = ev.evaluate(command: "fs.writeFile", windowLabel: "main")
        guard case .deny(reason: .explicitDeny(let cap, let perm)) = d else {
            Issue.record("expected explicitDeny, got \(d)")
            return
        }
        #expect(cap == "main")
        #expect(perm == "fs:deny-write")
    }

    @Test("Prefix wildcard fs.* matches descendants")
    func prefixGlob() {
        let perm = KSPermission(
            identifier: "fs:all",
            commandsAllow: ["fs.*"])
        let cap = KSCapability(
            identifier: "c", permissions: ["fs:all"])
        let ev = evaluator(permissions: [perm], capabilities: [cap])

        #expect(
            ev.evaluate(command: "fs.readFile", windowLabel: "main")
                == .allow(capability: "c"))
        #expect(
            ev.evaluate(command: "fs.writeFile", windowLabel: "main")
                == .allow(capability: "c"))
        // 다른 네임스페이스는 매칭되지 않음
        let d = ev.evaluate(command: "http.fetch", windowLabel: "main")
        if case .allow = d {
            Issue.record("fs.* should not match http.fetch")
        }
    }

    @Test("Window label glob prefix*")
    func windowGlob() {
        let perm = KSPermission(
            identifier: "p", commandsAllow: ["x"])
        let cap = KSCapability(
            identifier: "c",
            windows: ["settings-*"],
            permissions: ["p"])
        let ev = evaluator(permissions: [perm], capabilities: [cap])

        #expect(
            ev.evaluate(command: "x", windowLabel: "settings-general")
                == .allow(capability: "c"))
        let d = ev.evaluate(command: "x", windowLabel: "main")
        guard case .deny(reason: .noMatchingCapability) = d else {
            Issue.record("expected noMatchingCapability for label 'main', got \(d)")
            return
        }
    }

    @Test("Platform filter excludes non-matching OS")
    func platformFilter() {
        let perm = KSPermission(
            identifier: "p", commandsAllow: ["x"])
        let cap = KSCapability(
            identifier: "mac-only",
            permissions: ["p"],
            platforms: ["macOS"])
        let evWin = evaluator(
            permissions: [perm], capabilities: [cap], platform: "windows")
        let evMac = evaluator(
            permissions: [perm], capabilities: [cap], platform: "macOS")

        guard case .deny(reason: .noMatchingCapability) =
                evWin.evaluate(command: "x", windowLabel: "main")
        else {
            Issue.record("expected deny on windows")
            return
        }
        #expect(
            evMac.evaluate(command: "x", windowLabel: "main")
                == .allow(capability: "mac-only"))
    }

    @Test("Unknown permission identifier yields unknownPermission")
    func unknownPermission() {
        let cap = KSCapability(
            identifier: "c", permissions: ["does-not-exist"])
        let ev = evaluator(permissions: [], capabilities: [cap])

        let d = ev.evaluate(command: "x", windowLabel: "main")
        guard case .deny(reason: .unknownPermission(let c, let p)) = d else {
            Issue.record("expected unknownPermission, got \(d)")
            return
        }
        #expect(c == "c")
        #expect(p == "does-not-exist")
    }

    @Test("Matched capability but no permission allows → notInAllowlist")
    func notInAllowlist() {
        let perm = KSPermission(
            identifier: "p", commandsAllow: ["other"])
        let cap = KSCapability(
            identifier: "c", permissions: ["p"])
        let ev = evaluator(permissions: [perm], capabilities: [cap])

        let d = ev.evaluate(command: "x", windowLabel: "main")
        guard case .deny(reason: .notInAllowlist(let c)) = d else {
            Issue.record("expected notInAllowlist, got \(d)")
            return
        }
        #expect(c == "c")
    }

    @Test("Cache: repeated evaluation returns identical decision")
    func caching() {
        let perm = KSPermission(
            identifier: "p", commandsAllow: ["x"])
        let cap = KSCapability(
            identifier: "c", permissions: ["p"])
        let ev = evaluator(permissions: [perm], capabilities: [cap])

        let d1 = ev.evaluate(command: "x", windowLabel: "main")
        let d2 = ev.evaluate(command: "x", windowLabel: "main")
        #expect(d1 == d2)
        #expect(d1 == .allow(capability: "c"))
    }

    @Test("원격 origin은 remote.urls 매칭되는 capability만 사용")
    func remoteOriginFiltering() {
        let perm = KSPermission(
            identifier: "p", commandsAllow: ["x"])
        // local 전용 capability 와 remote(*.example.com) capability 분리.
        let localCap = KSCapability(
            identifier: "local-only", permissions: ["p"], local: true)
        let remoteCap = KSCapability(
            identifier: "remote",
            permissions: ["p"],
            local: false,
            remote: KSRemoteOriginConfig(urls: ["https://*.example.com"]))
        let ev = evaluator(
            permissions: [perm],
            capabilities: [localCap, remoteCap])

        // ks:// origin 은 local 매칭.
        let dLocal = ev.evaluate(
            command: "x", windowLabel: "main", origin: "ks://app/")
        #expect(dLocal == .allow(capability: "local-only"))

        // 원격 매칭 origin 은 remote capability 매칭.
        let dRemote = ev.evaluate(
            command: "x", windowLabel: "main",
            origin: "https://api.example.com")
        #expect(dRemote == .allow(capability: "remote"))

        // 미허용 원격 origin 은 어떤 capability도 매칭하지 않음.
        let dDenied = ev.evaluate(
            command: "x", windowLabel: "main",
            origin: "https://evil.com")
        guard case .deny(reason: .noMatchingCapability) = dDenied else {
            Issue.record("expected noMatchingCapability, got \(dDenied)")
            return
        }
    }
}

// MARK: - Pattern matcher 직접 검증

@Suite("KSPermission.matches — glob rules")
struct KSPermissionMatchesTests {

    @Test("Exact match")
    func exact() {
        #expect(KSPermission.matches("fs.readFile", pattern: "fs.readFile"))
        #expect(!KSPermission.matches("fs.readFile", pattern: "fs.writeFile"))
    }

    @Test("Star matches everything")
    func star() {
        #expect(KSPermission.matches("anything", pattern: "*"))
        #expect(KSPermission.matches("a.b.c", pattern: "*"))
    }

    @Test("prefix.* matches descendants and the root token")
    func dotStar() {
        #expect(KSPermission.matches("fs.read", pattern: "fs.*"))
        #expect(KSPermission.matches("fs.deep.nested", pattern: "fs.*"))
        // 구현 상 root token도 매칭한다.
        #expect(KSPermission.matches("fs", pattern: "fs.*"))
        #expect(!KSPermission.matches("http.fetch", pattern: "fs.*"))
        #expect(!KSPermission.matches("fsx", pattern: "fs.*"))
    }
}
