// MARK: - 오류

public import Foundation

// MARK: - PATH 조회

/// 시스템 PATH에서 `name`의 전체 URL을 반환하거나, 없으면 `nil`을 반환한다.

// MARK: - 실행기

/// `command`를 `arguments`와 함께 실행하며 stdio를 상속받는다. 종료를 기다린다.
/// 실행파일이 없거나 리턴 코드가 0이 아닐 때 `ShellError`를 던진다.

/// `command`를 `arguments`와 함께 백그라운드 실행하고 `Process` 핸들을 반환한다.

/// 셸에서 단일 커맨드 라인을 실행하고 종료를 기다린다.

/// 셸에서 단일 커맨드 라인을 백그라운드 실행하고 `Process` 핸들을 반환한다.

public enum ShellError: Error, CustomStringConvertible {
    case commandNotFound(String)
    case nonZeroExit(Int32)
    case shellUnavailable

    public var description: String {
        switch self {
        case .commandNotFound(let cmd): return "'\(cmd)' not found in PATH."
        case .nonZeroExit(let code): return "Process exited with code \(code)."
        case .shellUnavailable: return "No supported shell executable found."
        }
    }
}
public func findExecutable(named name: String) -> URL? {
    let env = ProcessInfo.processInfo.environment
    // Windows는 `Path`, 그 외 플랫폼은 `PATH`를 사용한다.
    let path = env["PATH"] ?? env["Path"] ?? ""
    let separator: Character = path.contains(";") ? ";" : ":"
    #if os(Windows)
        // Windows: PATHEXT-style 확장자가 붙은 매치만 반환한다.
        // Node.js 설치 디렉터리의 bash 스크립트 `npm` (확장자 없음)이
        // `npm.cmd`보다 먼저 매치되면 Process가 실행 불가능한 셸 스크립트를
        // 반환해 ERROR_BAD_EXE_FORMAT(193, Foundation Cocoa 3584)이 발생한다.
        // 정확한 확장자를 포함한 이름(예: "npm.cmd")은 그대로 매치된다.
        let suffixes = [".exe", ".cmd", ".bat", ".com"]
    #else
        let suffixes = [""]
    #endif
    for raw in path.split(separator: separator, omittingEmptySubsequences: true) {
        let dir = URL(fileURLWithPath: String(raw))
        for suffix in suffixes {
            let candidate = dir.appendingPathComponent("\(name)\(suffix)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
    }
    return nil
}
@discardableResult
public func shell(
    command: String,
    arguments: [String] = [],
    in directory: String? = nil,
    environment: [String: String]? = nil
) throws -> Int32 {
    let process = try makeProcess(
        command: command, arguments: arguments,
        in: directory, environment: environment)
    try process.run()
    process.waitUntilExit()
    let status = process.terminationStatus
    if status != 0 { throw ShellError.nonZeroExit(status) }
    return status
}
public func spawn(
    command: String,
    arguments: [String] = [],
    in directory: String? = nil,
    environment: [String: String]? = nil
) throws -> Process {
    let process = try makeProcess(
        command: command, arguments: arguments,
        in: directory, environment: environment)
    try process.run()
    return process
}

/// Windows에서 `.cmd`/`.bat` 파일은 Process API가 직접 실행할 수 없어
/// (`ERROR_BAD_EXE_FORMAT` 193) `cmd.exe /c` 로 감싸야 한다.
/// npm/pnpm/yarn 등 Node 도구가 모두 `.cmd` 셰어이므로 필수.
private func makeProcess(
    command: String,
    arguments: [String],
    in directory: String?,
    environment: [String: String]? = nil
)
    throws -> Process
{
    guard let url = findExecutable(named: command) else {
        throw ShellError.commandNotFound(command)
    }
    let process = Process()
    if let environment {
        // 부모 환경을 상속한 뒤 호출자 키를 덮어씌운다 — 비어있는 dict가
        // PATH/USERPROFILE 등 핵심 변수를 날려버리는 것을 막는다.
        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment { env[k] = v }
        process.environment = env
    }
    #if os(Windows)
        let ext = url.pathExtension.lowercased()
        if ext == "cmd" || ext == "bat" {
            // `.cmd`/`.bat`는 Process API로 직접 실행할 수 없고 (193 ERROR_BAD_EXE_FORMAT),
            // `cmd.exe /c`는 공백 포함 경로(`C:\Program Files\nodejs\npm.cmd`) 인용을 정확히
            // 표현하기 어렵다 (cmd /s 규약 vs Foundation 자동 quoting 충돌).
            // PowerShell의 `&` call 연산자는 따옴표/공백을 안전하게 처리하므로
            // pwsh/powershell을 통해 실행한다.
            let psURL =
                findExecutable(named: "pwsh") ?? findExecutable(named: "powershell")
            guard let psURL else { throw ShellError.shellUnavailable }
            process.executableURL = psURL
            // PowerShell 안에서 큰따옴표는 백틱으로 이스케이프.
            func psQuote(_ s: String) -> String {
                let escaped = s.replacingOccurrences(of: "'", with: "''")
                return "'\(escaped)'"
            }
            let invocation =
                "& \(psQuote(url.path)) "
                + arguments.map(psQuote).joined(separator: " ")
            process.arguments = [
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", invocation,
            ]
        } else {
            process.executableURL = url
            process.arguments = arguments
        }
    #else
        process.executableURL = url
        process.arguments = arguments
    #endif
    if let directory {
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
    }
    return process
}
@discardableResult
public func shell(commandLine: String, in directory: String? = nil) throws -> Int32 {
    let process = try makeShellProcess(commandLine: commandLine, in: directory)
    try process.run()
    process.waitUntilExit()
    let status = process.terminationStatus
    if status != 0 { throw ShellError.nonZeroExit(status) }
    return status
}
public func spawn(commandLine: String, in directory: String? = nil) throws -> Process {
    let process = try makeShellProcess(commandLine: commandLine, in: directory)
    try process.run()
    return process
}
private func makeShellProcess(commandLine: String, in directory: String?) throws -> Process {
    let process = Process()
    #if os(Windows)
        let shellURL = findExecutable(named: "pwsh") ?? findExecutable(named: "powershell")
        guard let shellURL else { throw ShellError.shellUnavailable }
        process.executableURL = shellURL
        process.arguments = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", commandLine]
    #else
        guard let shellURL = findExecutable(named: "sh") else { throw ShellError.shellUnavailable }
        process.executableURL = shellURL
        process.arguments = ["-lc", commandLine]
    #endif
    if let directory {
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
    }
    return process
}
