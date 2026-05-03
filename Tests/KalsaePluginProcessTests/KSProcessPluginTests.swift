import Foundation
import KalsaeCore
import Testing

@testable import KalsaePluginProcess

@Suite("KSProcessPlugin")
struct KSProcessPluginTests {

    // MARK: - 1. 명령 등록 확인

    @Test("setup 후 4개 명령이 등록된다")
    func setupRegistersAllCommands() async throws {
        let ctx = TestPluginContext()
        let plugin = KSProcessPlugin()
        try await plugin.setup(ctx)

        let registered = await ctx.registry.registered()
        #expect(registered.contains("kalsae.process.spawn"))
        #expect(registered.contains("kalsae.process.write"))
        #expect(registered.contains("kalsae.process.kill"))
        #expect(registered.contains("kalsae.process.wait"))
    }

    // MARK: - 2. allowlist 보안 — 미등록 프로그램 거부

    @Test("allowlist 없이 spawn하면 commandNotAllowed를 반환한다")
    func spawnDeniedWithoutAllowlist() async throws {
        let ctx = TestPluginContext()
        let plugin = KSProcessPlugin(config: KSProcessPluginConfig(allowlist: []))
        try await plugin.setup(ctx)

        #if os(Windows)
            let program = "C:\\Windows\\System32\\cmd.exe"
        #else
            let program = "/bin/echo"
        #endif
        let opts = KSSpawnOptions(program: program, args: [])
        let argsData = try JSONEncoder().encode(opts)

        let result = await ctx.registry.dispatch(name: "kalsae.process.spawn", args: argsData)
        guard case .failure(let error) = result else {
            Issue.record("Expected failure but got success")
            return
        }
        #expect(error.code == .commandNotAllowed)
    }

    @Test("allowlist에 없는 경로는 commandNotAllowed를 반환한다")
    func spawnDeniedForUnlistedPath() async throws {
        let ctx = TestPluginContext()
        let plugin = KSProcessPlugin(config: KSProcessPluginConfig(allowlist: ["/some/other/binary"]))
        try await plugin.setup(ctx)

        #if os(Windows)
            let program = "C:\\Windows\\System32\\cmd.exe"
        #else
            let program = "/bin/echo"
        #endif
        let opts = KSSpawnOptions(program: program, args: [])
        let argsData = try JSONEncoder().encode(opts)

        let result = await ctx.registry.dispatch(name: "kalsae.process.spawn", args: argsData)
        guard case .failure(let error) = result else {
            Issue.record("Expected failure but got success")
            return
        }
        #expect(error.code == .commandNotAllowed)
    }

    // MARK: - 3. spawn + stdout 이벤트

    @Test("spawn은 stdout 이벤트를 발행하고 exit 이벤트로 종료한다")
    func spawnEmitsStdoutAndExit() async throws {
        #if os(Windows)
            let program = "C:\\Windows\\System32\\cmd.exe"
            let args = ["/c", "echo hello"]
        #elseif os(macOS) || os(Linux)
            let program = "/bin/echo"
            let args = ["hello"]
        #else
            return  // iOS/Android 빌드 시 건너뜀
        #endif

        let ctx = TestPluginContext()
        let plugin = KSProcessPlugin(config: KSProcessPluginConfig(allowlist: [program]))
        try await plugin.setup(ctx)

        let opts = KSSpawnOptions(program: program, args: args)
        let argsData = try JSONEncoder().encode(opts)

        let spawnResult = await ctx.registry.dispatch(name: "kalsae.process.spawn", args: argsData)
        guard case .success(let handleData) = spawnResult else {
            Issue.record("spawn failed: \(spawnResult)")
            return
        }
        let handle = try JSONDecoder().decode(KSChildHandle.self, from: handleData)
        #expect(!handle.id.isEmpty)

        // exit 이벤트 대기 (최대 5초)
        let exitReceived = await ctx.waitForEvent("kalsae.process.exit", timeout: .seconds(5))
        #expect(exitReceived != nil, "exit 이벤트가 5초 내에 도착해야 한다")

        // stdout 이벤트에 데이터가 있는지 확인
        let stdoutEvents = await ctx.events(named: "kalsae.process.stdout")
        #expect(!stdoutEvents.isEmpty, "stdout 이벤트가 최소 1개 있어야 한다")
    }

    // MARK: - 4. kill

    @Test("kill 후 exit 이벤트가 도착한다")
    func killSendsExitEvent() async throws {
        #if os(Windows)
            // ping을 써서 오래 실행되는 프로세스 시뮬레이션
            let program = "C:\\Windows\\System32\\ping.exe"
            let args = ["-n", "30", "127.0.0.1"]
        #elseif os(macOS) || os(Linux)
            let program = "/bin/sleep"
            let args = ["30"]
        #else
            return
        #endif

        let ctx = TestPluginContext()
        let plugin = KSProcessPlugin(config: KSProcessPluginConfig(allowlist: [program]))
        try await plugin.setup(ctx)

        let opts = KSSpawnOptions(program: program, args: args)
        let spawnResult = await ctx.registry.dispatch(
            name: "kalsae.process.spawn",
            args: try JSONEncoder().encode(opts))
        guard case .success(let handleData) = spawnResult else {
            Issue.record("spawn failed: \(spawnResult)")
            return
        }
        let handle = try JSONDecoder().decode(KSChildHandle.self, from: handleData)

        // kill 호출
        let killArg = KSKillArg(handle: handle.id)
        let killResult = await ctx.registry.dispatch(
            name: "kalsae.process.kill",
            args: try JSONEncoder().encode(killArg))
        guard case .success = killResult else {
            Issue.record("kill failed: \(killResult)")
            return
        }

        // exit 이벤트 대기 (최대 5초)
        let exitEvent = await ctx.waitForEvent("kalsae.process.exit", timeout: .seconds(5))
        #expect(exitEvent != nil, "kill 후 exit 이벤트가 5초 내에 도착해야 한다")
    }

    // MARK: - 5. wait

    @Test("wait는 프로세스 종료 정보를 반환한다")
    func waitReturnsExitInfo() async throws {
        #if os(Windows)
            let program = "C:\\Windows\\System32\\cmd.exe"
            let args = ["/c", "exit 0"]
        #elseif os(macOS) || os(Linux)
            let program = "/bin/sh"
            let args = ["-c", "exit 0"]
        #else
            return
        #endif

        let ctx = TestPluginContext()
        let plugin = KSProcessPlugin(config: KSProcessPluginConfig(allowlist: [program]))
        try await plugin.setup(ctx)

        let spawnResult = await ctx.registry.dispatch(
            name: "kalsae.process.spawn",
            args: try JSONEncoder().encode(KSSpawnOptions(program: program, args: args)))
        guard case .success(let handleData) = spawnResult else {
            Issue.record("spawn failed: \(spawnResult)")
            return
        }
        let handle = try JSONDecoder().decode(KSChildHandle.self, from: handleData)

        let waitArg = KSWaitArg(handle: handle.id)
        let waitResult = await ctx.registry.dispatch(
            name: "kalsae.process.wait",
            args: try JSONEncoder().encode(waitArg))
        guard case .success(let infoData) = waitResult else {
            Issue.record("wait failed: \(waitResult)")
            return
        }
        let exitInfo = try JSONDecoder().decode(KSExitInfo.self, from: infoData)
        // 정상 종료 시 code가 있어야 한다 (0)
        #expect(exitInfo.code == 0)
    }

    // MARK: - 6. 알 수 없는 핸들에 대한 오류

    @Test("알 수 없는 핸들로 wait하면 commandNotFound를 반환한다")
    func waitUnknownHandleReturnsError() async throws {
        let ctx = TestPluginContext()
        let plugin = KSProcessPlugin()
        try await plugin.setup(ctx)

        let arg = KSWaitArg(handle: "non-existent-handle")
        let result = await ctx.registry.dispatch(
            name: "kalsae.process.wait",
            args: try JSONEncoder().encode(arg))
        guard case .failure(let error) = result else {
            Issue.record("Expected failure but got success")
            return
        }
        #expect(error.code == .commandNotFound)
    }
}

// MARK: - 테스트 헬퍼

/// 이벤트를 캡처하는 테스트용 KSPluginContext 구현.
private final class TestPluginContext: KSPluginContext, @unchecked Sendable {
    let registry = KSCommandRegistry()
    var platform: any KSPlatform { TestPlatform() }

    private var _events: [(name: String, data: Data)] = []
    private var _waiters: [(String, CheckedContinuation<Data?, Never>)] = []
    private let lock = NSLock()

    func emit(_ event: String, payload: sending any Encodable) async throws(KSError) {
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        lock.withLock {
            _events.append((name: event, data: data))
            let matching = _waiters.firstIndex(where: { $0.0 == event })
            if let idx = matching {
                let (_, cont) = _waiters.remove(at: idx)
                cont.resume(returning: data)
            }
        }
    }

    func events(named name: String) async -> [Data] {
        lock.withLock {
            _events.filter { $0.name == name }.map { $0.data }
        }
    }

    /// 지정된 이름의 이벤트가 올 때까지 `timeout`만큼 기다린다.
    func waitForEvent(_ name: String, timeout: Duration) async -> Data? {
        // 이미 도착한 이벤트가 있으면 즉시 반환
        let existing = lock.withLock {
            _events.first(where: { $0.name == name })?.data
        }
        if let d = existing { return d }

        // 아직 없으면 continuation으로 대기
        return await withCheckedContinuation { cont in
            lock.withLock {
                _waiters.append((name, cont))
            }
            Task {
                try? await Task.sleep(for: timeout)
                let removed = self.lock.withLock {
                    if let idx = self._waiters.firstIndex(where: { $0.0 == name }) {
                        self._waiters.remove(at: idx)
                        return true
                    }
                    return false
                }
                if removed {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

/// 테스트용 최소 KSPlatform 구현.
private struct TestPlatform: KSPlatform {
    var name: String { "test" }
    var windows: any KSWindowBackend { fatalError("not used") }
    var dialogs: any KSDialogBackend { fatalError("not used") }
    var menus: any KSMenuBackend { fatalError("not used") }
    var notifications: any KSNotificationBackend { fatalError("not used") }
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
        fatalError("not used")
    }
}
