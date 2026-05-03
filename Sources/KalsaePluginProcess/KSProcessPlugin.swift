import Foundation
public import KalsaeCore

// MARK: - KSProcessPlugin 설정

/// `KSProcessPlugin` 초기화 설정.
///
/// ### 보안
/// `allowlist`에 포함되지 않은 실행 파일 경로는 `spawn()` 시 `.commandNotAllowed`를 반환한다.
/// 기본값(`[]`)은 모든 spawn을 거부한다 — 명시적으로 허용 목록을 지정해야 한다.
///
/// ```swift
/// KSProcessPluginConfig(allowlist: ["/usr/bin/echo", "/usr/bin/ls"])
/// ```
public struct KSProcessPluginConfig: Sendable {
    /// spawn을 허용할 실행 파일 전체 경로 목록.
    /// 빈 배열(`[]`, 기본값)이면 모든 spawn이 거부된다.
    public var allowlist: [String]

    public init(allowlist: [String] = []) {
        self.allowlist = allowlist
    }
}

// MARK: - KSProcessPlugin

/// 자식 프로세스 생성/IO/종료를 JS 프론트엔드에 노출하는 Kalsae 플러그인.
///
/// ### 등록 명령
/// | 명령 | 인수 | 반환 |
/// |---|---|---|
/// | `kalsae.process.spawn` | `KSSpawnOptions` | `KSChildHandle` |
/// | `kalsae.process.write` | `{ handle, data: base64 }` | — |
/// | `kalsae.process.kill`  | `{ handle }` | — |
/// | `kalsae.process.wait`  | `{ handle }` | `KSExitInfo` |
///
/// ### 발행 이벤트
/// | 이벤트 | 페이로드 |
/// |---|---|
/// | `kalsae.process.stdout` | `{ handle, data: base64 }` |
/// | `kalsae.process.stderr` | `{ handle, data: base64 }` |
/// | `kalsae.process.exit`   | `{ handle, code?, signal? }` |
///
/// ### 사용 예
/// ```swift
/// let config = KSProcessPluginConfig(allowlist: ["/usr/bin/echo"])
/// try await app.install([KSProcessPlugin(config: config)])
/// ```
public struct KSProcessPlugin: KSPlugin {
    public static let namespace = "kalsae.process"

    private let config: KSProcessPluginConfig

    /// - Parameter config: 보안 설정 (allowlist). 기본값은 전부 거부.
    public init(config: KSProcessPluginConfig = KSProcessPluginConfig()) {
        self.config = config
    }

    public func setup(_ ctx: any KSPluginContext) async throws(KSError) {
        let manager = KSProcessManager(ctx: ctx)
        let allowlist = config.allowlist

        await ksProcessRegister(ctx.registry, "kalsae.process.spawn") {
            (opts: KSSpawnOptions) async throws(KSError) -> KSChildHandle in
            try await manager.spawn(opts: opts, allowlist: allowlist)
        }

        await ksProcessRegister(ctx.registry, "kalsae.process.write") {
            (arg: KSWriteArg) async throws(KSError) -> KSEmpty in
            try await manager.write(id: arg.handle, base64Data: arg.data)
            return KSEmpty()
        }

        await ksProcessRegister(ctx.registry, "kalsae.process.kill") {
            (arg: KSKillArg) async throws(KSError) -> KSEmpty in
            try await manager.kill(id: arg.handle)
            return KSEmpty()
        }

        await ksProcessRegister(ctx.registry, "kalsae.process.wait") {
            (arg: KSWaitArg) async throws(KSError) -> KSExitInfo in
            try await manager.wait(id: arg.handle)
        }
    }
}

// MARK: - 내부 등록 헬퍼

/// Codable 타입 기반의 명령을 KSCommandRegistry에 등록하는 헬퍼.
/// KSBuiltinCommands.register와 동일한 역할이지만 플러그인 모듈 내부용.
func ksProcessRegister<In: Codable & Sendable, Out: Codable & Sendable>(
    _ registry: KSCommandRegistry,
    _ name: String,
    handler: @Sendable @escaping (In) async throws(KSError) -> Out
) async {
    await registry.register(name) { data -> Result<Data, KSError> in
        let input: In
        do {
            input = try JSONDecoder().decode(
                In.self,
                from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            return .failure(
                KSError(
                    code: .commandDecodeFailed,
                    message: "decode failed for \(name): \(error)"))
        }
        do {
            let out = try await handler(input)
            let encoded = try JSONEncoder().encode(out)
            return .success(encoded)
        } catch let e as KSError {
            // 혼합 throw 지점 (JSONEncoder + typed throws handler) — AGENTS §4
            return .failure(e)
        } catch {
            return .failure(
                KSError(
                    code: .commandExecutionFailed,
                    message: "\(error)"))
        }
    }
}

// MARK: - 빈 응답 타입

/// 반환 값이 없는 명령의 응답 타입.
struct KSEmpty: Codable, Sendable {}
