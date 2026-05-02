public import Foundation

// MARK: - 오류

public enum ShellError: Error, CustomStringConvertible {
    case commandNotFound(String)
    case nonZeroExit(Int32)
    case shellUnavailable

    public var description: String {
        switch self {
        case .commandNotFound(let cmd): return "'\(cmd)' not found in PATH."
        case .nonZeroExit(let code):    return "Process exited with code \(code)."
        case .shellUnavailable:         return "No supported shell executable found."
        }
    }
}

// MARK: - PATH 조회

/// 시스템 PATH에서 `name`의 전체 URL을 반환하거나, 없으면 `nil`을 반환한다.
public func findExecutable(named name: String) -> URL? {
    let env  = ProcessInfo.processInfo.environment
    // Windows는 `Path`, 그 외 플랫폼은 `PATH`를 사용한다.
    let path = env["PATH"] ?? env["Path"] ?? ""
    let separator: Character = path.contains(";") ? ";" : ":"
#if os(Windows)
    let suffixes = ["", ".exe", ".cmd", ".bat"]
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

// MARK: - 실행기

/// `command`를 `arguments`와 함께 실행하며 stdio를 상속받는다. 종료를 기다린다.
/// 실행파일이 없거나 리턴 코드가 0이 아닐 때 `ShellError`를 던진다.
@discardableResult
public func shell(command: String, arguments: [String] = [], in directory: String? = nil) throws -> Int32 {
    guard let url = findExecutable(named: command) else {
        throw ShellError.commandNotFound(command)
    }
    let process = Process()
    process.executableURL = url
    process.arguments = arguments
    if let dir = directory {
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
    }
    try process.run()
    process.waitUntilExit()
    let status = process.terminationStatus
    if status != 0 { throw ShellError.nonZeroExit(status) }
    return status
}

/// `command`를 `arguments`와 함께 백그라운드 실행하고 `Process` 핸들을 반환한다.
public func spawn(command: String, arguments: [String] = [], in directory: String? = nil) throws -> Process {
    guard let url = findExecutable(named: command) else {
        throw ShellError.commandNotFound(command)
    }
    let process = Process()
    process.executableURL = url
    process.arguments = arguments
    if let directory {
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
    }
    try process.run()
    return process
}

/// 셸에서 단일 커맨드 라인을 실행하고 종료를 기다린다.
@discardableResult
public func shell(commandLine: String, in directory: String? = nil) throws -> Int32 {
    let process = try makeShellProcess(commandLine: commandLine, in: directory)
    try process.run()
    process.waitUntilExit()
    let status = process.terminationStatus
    if status != 0 { throw ShellError.nonZeroExit(status) }
    return status
}

/// 셸에서 단일 커맨드 라인을 백그라운드 실행하고 `Process` 핸들을 반환한다.
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
