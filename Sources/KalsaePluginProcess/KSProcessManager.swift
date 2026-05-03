import Foundation
import KalsaeCore

// MARK: - ProcessEntry

/// Foundation.Process 래퍼.
/// 뮤테이션은 KSProcessManager 액터만 수행하지만, terminationHandler와
/// 파이프 펌프 스레드에서도 읽으므로 @unchecked Sendable.
private final class ProcessEntry: @unchecked Sendable {
    let process: Foundation.Process
    var stdinPipe: Pipe?

    private var _exitInfo: KSExitInfo?
    private var _waiters: [CheckedContinuation<KSExitInfo, Never>] = []

    init(_ process: Foundation.Process) {
        self.process = process
    }

    var exitInfo: KSExitInfo? { _exitInfo }

    /// 종료 정보를 기록하고 대기 중인 모든 continuation을 재개한다.
    func resolveExit(_ info: KSExitInfo) {
        _exitInfo = info
        let waiters = _waiters
        _waiters = []
        for c in waiters { c.resume(returning: info) }
    }

    /// 이미 종료됐으면 즉시 재개, 아니면 종료 시까지 대기한다.
    func awaitExit() async -> KSExitInfo {
        if let info = _exitInfo { return info }
        return await withCheckedContinuation { cont in
            _waiters.append(cont)
        }
    }
}

// MARK: - KSProcessManager

/// KSProcessPlugin의 자식 프로세스 수명 주기를 관리하는 액터.
actor KSProcessManager {
    private var entries: [String: ProcessEntry] = [:]
    private let ctx: any KSPluginContext

    init(ctx: any KSPluginContext) {
        self.ctx = ctx
    }

    // MARK: spawn

    func spawn(opts: KSSpawnOptions, allowlist: [String]) async throws(KSError) -> KSChildHandle {
        guard allowlist.contains(opts.program) else {
            throw KSError(
                code: .commandNotAllowed,
                message: "'\(opts.program)' is not in the process allowlist. Add it to KSProcessPluginConfig.allowlist."
            )
        }

        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: opts.program)
        process.arguments = opts.args
        if let cwd = opts.cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        if let env = opts.env {
            process.environment = env
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe?
        if opts.pipeStdin {
            let p = Pipe()
            process.standardInput = p
            stdinPipe = p
        } else {
            process.standardInput = FileHandle.nullDevice
            stdinPipe = nil
        }

        let id = UUID().uuidString
        let entry = ProcessEntry(process)
        entry.stdinPipe = stdinPipe

        // 종료 핸들러 — terminationHandler는 임의 스레드에서 호출됨.
        // entry와 ctx는 Sendable이므로 Task로 안전하게 캡처.
        let capturedCtx = ctx
        process.terminationHandler = { p in
            let rawCode = p.terminationStatus
            let reason = p.terminationReason
            let exitCode: Int32? = (reason == .exit) ? rawCode : nil
            let signal: Int32? = (reason == .uncaughtSignal) ? rawCode : nil
            let info = KSExitInfo(code: exitCode, signal: signal)
            Task {
                entry.resolveExit(info)
                try? await capturedCtx.emit(
                    "kalsae.process.exit",
                    payload: KSProcessExitEvent(handle: id, code: exitCode, signal: signal))
            }
        }

        do {
            try process.run()
        } catch {
            throw KSError(
                code: .shellInvocationFailed,
                message: "failed to launch '\(opts.program)': \(error.localizedDescription)")
        }

        entries[id] = entry

        // 파이프 펌프 시작 — 백그라운드 스레드에서 읽고 이벤트 발행
        startPumper(pipe: stdoutPipe, handleID: id, event: "kalsae.process.stdout", ctx: capturedCtx)
        startPumper(pipe: stderrPipe, handleID: id, event: "kalsae.process.stderr", ctx: capturedCtx)

        return KSChildHandle(id: id)
    }

    // MARK: write

    func write(id: String, base64Data: String) async throws(KSError) {
        guard let entry = entries[id] else {
            throw KSError(code: .commandNotFound, message: "process '\(id)' not found")
        }
        guard let pipe = entry.stdinPipe else {
            throw KSError(
                code: .commandNotAllowed,
                message: "process '\(id)' was spawned without pipeStdin=true")
        }
        guard let data = Data(base64Encoded: base64Data) else {
            throw KSError(code: .invalidArgument, message: "data is not valid base64")
        }
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw KSError(code: .ioFailed, message: "stdin write failed: \(error.localizedDescription)")
        }
    }

    // MARK: kill

    func kill(id: String) async throws(KSError) {
        guard let entry = entries[id] else {
            throw KSError(code: .commandNotFound, message: "process '\(id)' not found")
        }
        if entry.process.isRunning {
            entry.process.terminate()
        }
    }

    // MARK: wait

    func wait(id: String) async throws(KSError) -> KSExitInfo {
        guard let entry = entries[id] else {
            throw KSError(code: .commandNotFound, message: "process '\(id)' not found")
        }
        return await entry.awaitExit()
    }
}

// MARK: - 파이프 펌프

/// 파이프에서 데이터를 읽어 이벤트를 발행하는 백그라운드 스레드를 시작한다.
/// `availableData`는 파이프의 쓰기 끝이 열려 있는 동안 데이터가
/// 없으면 블로킹된다. 쓰기 끝이 닫히면 빈 Data를 반환해 루프가 종료된다.
private func startPumper(
    pipe: Pipe,
    handleID: String,
    event: String,
    ctx: any KSPluginContext
) {
    let fh = pipe.fileHandleForReading
    Thread.detachNewThread {
        while true {
            let data = fh.availableData
            if data.isEmpty { break }
            let b64 = data.base64EncodedString()
            Task {
                try? await ctx.emit(
                    event,
                    payload: KSProcessDataEvent(handle: handleID, data: b64))
            }
        }
    }
}
