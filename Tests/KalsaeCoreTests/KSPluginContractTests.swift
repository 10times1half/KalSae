import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSPluginContract")
struct KSPluginContractTests {

    // MARK: - 1. 네임스페이스 검증

    @Test("유효한 네임스페이스는 검증을 통과한다")
    func validNamespacePasses() throws {
        // 아래 입력이 모두 throw 없이 통과해야 한다.
        try ksValidatePluginNamespace("myco.analytics")
        try ksValidatePluginNamespace("a")
        try ksValidatePluginNamespace("vendor.feature.v2")
    }

    @Test("빈 네임스페이스는 configInvalid를 throw한다")
    func emptyNamespaceFails() {
        var caught: KSError? = nil
        do throws(KSError) {
            try ksValidatePluginNamespace("")
        } catch {
            caught = error
        }
        #expect(caught?.code == .configInvalid)
    }

    @Test("공백 포함 네임스페이스는 configInvalid를 throw한다")
    func whitespaceNamespaceFails() {
        var caught: KSError? = nil
        do throws(KSError) {
            try ksValidatePluginNamespace("my co.analytics")
        } catch {
            caught = error
        }
        #expect(caught?.code == .configInvalid)
    }

    @Test("__ks. prefix 네임스페이스는 configInvalid를 throw한다")
    func reservedPrefixFails() {
        var caught: KSError? = nil
        do throws(KSError) {
            try ksValidatePluginNamespace("__ks.internal")
        } catch {
            caught = error
        }
        #expect(caught?.code == .configInvalid)
    }

    // MARK: - 2. setup 시 명령 등록

    @Test("setup이 KSCommandRegistry에 명령을 등록한다")
    func setupRegistersCommand() async throws {
        let registry = KSCommandRegistry()
        let plugin = SpyPlugin()
        let ctx = SpyPluginContext(registry: registry)
        try await plugin.setup(ctx)

        let registered = await registry.registered()
        #expect(registered.contains("spy.ping"))
    }

    // MARK: - 3. teardown 기본 구현이 존재한다

    @Test("teardown 기본 구현은 no-op이다")
    func defaultTeardownIsNoOp() async throws {
        let registry = KSCommandRegistry()
        let plugin = SpyPlugin()
        let ctx = SpyPluginContext(registry: registry)

        // setup 없이 teardown만 호출 — 에러 없이 완료해야 한다.
        await plugin.teardown(ctx)
        #expect(await registry.registered().isEmpty)
    }
}

// MARK: - 테스트 헬퍼

/// 테스트용 최소 KSPlugin 구현.
private struct SpyPlugin: KSPlugin {
    static let namespace = "spy"

    func setup(_ ctx: any KSPluginContext) async throws(KSError) {
        await ctx.registry.register("spy.ping") { _ in
            let data = try? JSONEncoder().encode("pong")
            return .success(data ?? Data())
        }
    }
    // teardown은 기본 구현(no-op) 사용
}

/// 테스트용 최소 KSPluginContext 구현.
private struct SpyPluginContext: KSPluginContext {
    let registry: KSCommandRegistry
    var platform: any KSPlatform { SpyPlatform() }

    func emit(_ event: String, payload: sending any Encodable) async throws(KSError) {}
}

/// 테스트용 최소 KSPlatform 구현.
private struct SpyPlatform: KSPlatform {
    var name: String { "spy" }
    var windows: any KSWindowBackend { fatalError("not used in tests") }
    var dialogs: any KSDialogBackend { fatalError("not used in tests") }
    var menus: any KSMenuBackend { fatalError("not used in tests") }
    var notifications: any KSNotificationBackend { fatalError("not used in tests") }
    var tray: (any KSTrayBackend)? { nil }
    var shell: (any KSShellBackend)? { nil }
    var clipboard: (any KSClipboardBackend)? { nil }
    var accelerators: (any KSAcceleratorBackend)? { nil }
    var autostart: (any KSAutostartBackend)? { nil }
    var deepLink: (any KSDeepLinkBackend)? { nil }

    func run(
        config: KSConfig,
        configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
    ) async throws(KSError) -> Never {
        fatalError("not used in tests")
    }
}
