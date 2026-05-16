import Foundation
import Testing

@testable import KalsaeCore

// MARK: - In-memory test backend

private actor InMemoryCredentialBackend: KSCredentialBackend {
    private var store: [KSCredentialKey: Data] = [:]

    func set(_ key: KSCredentialKey, secret: Data) async throws(KSError) {
        store[key] = secret
    }

    func get(_ key: KSCredentialKey) async throws(KSError) -> Data? {
        store[key]
    }

    func delete(_ key: KSCredentialKey) async throws(KSError) {
        store.removeValue(forKey: key)
    }

    func list(service: String) async throws(KSError) -> [KSCredentialKey] {
        store.keys.filter { $0.service == service }.sorted { $0.account < $1.account }
    }

    func snapshot() async -> [KSCredentialKey: Data] { store }
}

// MARK: - Tests

@Suite("KSSecretScope")
struct KSSecretScopeTests {
    @Test("defaults are safe (disabled, empty allowlist)")
    func defaultsAreSafe() {
        let scope = KSSecretScope()
        #expect(scope.enabled == false)
        #expect(scope.allowedServices.isEmpty)
        #expect(scope.maxSecretBytes == 64 * 1024)
        #expect(scope.allowList == true)
        #expect(scope.allowDelete == true)
    }

    @Test("permits requires exact match or wildcard")
    func permitsMatching() {
        let strict = KSSecretScope(
            enabled: true, allowedServices: ["github", "openai"],
            maxSecretBytes: 1024, allowList: true, allowDelete: true)
        #expect(strict.permits(service: "github"))
        #expect(strict.permits(service: "openai"))
        #expect(!strict.permits(service: "stripe"))
        #expect(!strict.permits(service: ""))

        let open = KSSecretScope(
            enabled: true, allowedServices: ["*"],
            maxSecretBytes: 1024, allowList: true, allowDelete: true)
        #expect(open.permits(service: "anything"))
    }

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let scope = KSSecretScope(
            enabled: true,
            allowedServices: ["a", "b"],
            maxSecretBytes: 2048,
            allowList: false,
            allowDelete: false)
        let data = try JSONEncoder().encode(scope)
        let decoded = try JSONDecoder().decode(KSSecretScope.self, from: data)
        #expect(decoded == scope)
    }
}

@Suite("KSCredentialKey")
struct KSCredentialKeyTests {
    @Test("Hashable+Equatable+Codable")
    func basics() throws {
        let a = KSCredentialKey(service: "svc", account: "alice")
        let b = KSCredentialKey(service: "svc", account: "alice")
        let c = KSCredentialKey(service: "svc", account: "bob")
        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
        let data = try JSONEncoder().encode(a)
        let decoded = try JSONDecoder().decode(KSCredentialKey.self, from: data)
        #expect(decoded == a)
    }
}

@Suite("InMemoryCredentialBackend round-trip")
struct InMemoryBackendRoundTripTests {
    @Test("set / get / delete / list")
    func roundTrip() async throws {
        let backend = InMemoryCredentialBackend()
        let k1 = KSCredentialKey(service: "svc", account: "a")
        let k2 = KSCredentialKey(service: "svc", account: "b")
        let payload = Data("hello".utf8)

        try await backend.set(k1, secret: payload)
        try await backend.set(k2, secret: Data("world".utf8))

        let got = try await backend.get(k1)
        #expect(got == payload)

        let listed = try await backend.list(service: "svc")
        #expect(listed.count == 2)
        #expect(listed.contains(k1))
        #expect(listed.contains(k2))

        try await backend.delete(k1)
        let after = try await backend.get(k1)
        #expect(after == nil)
    }
}

@Suite("KSBuiltinCommands secret scope enforcement")
struct KSBuiltinCommandsSecretTests {
    // 핵심 행위 검증: scope.allowedServices, bundleId prefix, base64 round-trip,
    // maxSecretBytes, allowDelete/allowList.

    @Test("registerSecretCommands stores under bundleId-prefixed service")
    func storesWithPrefix() async throws {
        let backend = InMemoryCredentialBackend()
        let registry = KSCommandRegistry()
        let scope = KSSecretScope(
            enabled: true, allowedServices: ["github"],
            maxSecretBytes: 1024, allowList: true, allowDelete: true)
        await KSBuiltinCommands.registerSecretCommands(
            into: registry, backend: backend, scope: scope, bundleId: "com.example.App")

        // 직접 백엔드 로직(=registerSecretCommands가 의존하는 정규화)을 확인하기
        // 위해 registry 핸들러를 통해 set을 호출하고 백엔드 snapshot을 확인한다.
        let body = #"{"service":"github","account":"alice","secret":"#
            + #""\#(Data("token-1".utf8).base64EncodedString())"}"#
        let result = await registry.dispatch(
            name: "__ks.secret.set", args: Data(body.utf8))
        if case .failure(let err) = result {
            Issue.record("set failed: \(err)")
        }

        let snap = await backend.snapshot()
        let key = KSCredentialKey(service: "com.example.App.github", account: "alice")
        #expect(snap[key] == Data("token-1".utf8))
    }

    @Test("set rejects services outside allowedServices")
    func rejectsDisallowedService() async throws {
        let backend = InMemoryCredentialBackend()
        let registry = KSCommandRegistry()
        let scope = KSSecretScope(
            enabled: true, allowedServices: ["github"],
            maxSecretBytes: 1024, allowList: true, allowDelete: true)
        await KSBuiltinCommands.registerSecretCommands(
            into: registry, backend: backend, scope: scope, bundleId: "com.example.App")

        let body = #"{"service":"stripe","account":"a","secret":""}"#
        let result = await registry.dispatch(
            name: "__ks.secret.set", args: Data(body.utf8))
        guard case .failure(let err) = result else {
            Issue.record("expected failure")
            return
        }
        #expect(err.code == .commandNotAllowed)
    }

    @Test("set rejects payload above maxSecretBytes")
    func rejectsOversized() async throws {
        let backend = InMemoryCredentialBackend()
        let registry = KSCommandRegistry()
        let scope = KSSecretScope(
            enabled: true, allowedServices: ["*"],
            maxSecretBytes: 8,
            allowList: true, allowDelete: true)
        await KSBuiltinCommands.registerSecretCommands(
            into: registry, backend: backend, scope: scope, bundleId: "")

        let oversized = Data(repeating: 0x41, count: 32).base64EncodedString()
        let body = #"{"service":"svc","account":"a","secret":"\#(oversized)"}"#
        let result = await registry.dispatch(
            name: "__ks.secret.set", args: Data(body.utf8))
        guard case .failure(let err) = result else {
            Issue.record("expected failure")
            return
        }
        #expect(err.code == .invalidArgument)
    }

    @Test("delete is blocked when scope.allowDelete=false")
    func deleteGuarded() async throws {
        let backend = InMemoryCredentialBackend()
        let registry = KSCommandRegistry()
        let scope = KSSecretScope(
            enabled: true, allowedServices: ["*"],
            maxSecretBytes: 1024, allowList: true, allowDelete: false)
        await KSBuiltinCommands.registerSecretCommands(
            into: registry, backend: backend, scope: scope, bundleId: "")

        let body = #"{"service":"svc","account":"a"}"#
        let result = await registry.dispatch(
            name: "__ks.secret.delete", args: Data(body.utf8))
        guard case .failure(let err) = result else {
            Issue.record("expected failure")
            return
        }
        #expect(err.code == .commandNotAllowed)
    }

    @Test("list strips bundleId prefix from returned service")
    func listStripsPrefix() async throws {
        let backend = InMemoryCredentialBackend()
        // 미리 prefix가 적용된 키를 백엔드에 심어둔다.
        try await backend.set(
            KSCredentialKey(service: "com.example.App.github", account: "alice"),
            secret: Data("x".utf8))
        try await backend.set(
            KSCredentialKey(service: "com.example.App.github", account: "bob"),
            secret: Data("y".utf8))

        let registry = KSCommandRegistry()
        let scope = KSSecretScope(
            enabled: true, allowedServices: ["github"],
            maxSecretBytes: 1024, allowList: true, allowDelete: true)
        await KSBuiltinCommands.registerSecretCommands(
            into: registry, backend: backend, scope: scope, bundleId: "com.example.App")

        let body = #"{"service":"github"}"#
        let result = await registry.dispatch(
            name: "__ks.secret.list", args: Data(body.utf8))
        guard case .success(let payload) = result else {
            Issue.record("list failed: \(result)")
            return
        }
        struct Out: Decodable { let items: [Item]; struct Item: Decodable { let service: String; let account: String } }
        let decoded = try JSONDecoder().decode(Out.self, from: payload)
        #expect(decoded.items.count == 2)
        // service 필드는 prefix가 제거된 값이어야 한다.
        for it in decoded.items {
            #expect(it.service == "github")
        }
        let accounts = Set(decoded.items.map(\.account))
        #expect(accounts == ["alice", "bob"])
    }
}
