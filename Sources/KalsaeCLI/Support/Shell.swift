public import Foundation

// MARK: - 오류

public enum ShellError: Error, CustomStringConvertible {
    case commandNotFound(String)
    case nonZeroExit(Int32)
    case shellUnavailable
    /// 임의의 진단 메시지를 그대로 노출하고 싶을 때 사용. PATH 결함이
    /// 아닌 설정/프로비저닝 오류에 `commandNotFound` 를 재사용하면
    /// "'...' not found in PATH." 로 잘못 표시되므로 해당 경우에 쓰일 채널.
    case message(String)

    public var description: String {
        switch self {
        case .commandNotFound(let cmd): return "'\(cmd)' not found in PATH."
        case .nonZeroExit(let code): return "Process exited with code \(code)."
        case .shellUnavailable: return "No supported shell executable found."
        case .message(let m): return m
        }
    }
}

// MARK: - PATH 조회

/// 시스템 PATH에서 `name`의 전체 URL을 반환하거나, 없으면 `nil`을 반환한다.
/// Windows에서는 `.exe`/`.cmd`/`.bat`/`.com` 확장자를 가진 매치만 반환한다 —
/// 확장자 없는 Node bash 셰어가 `.cmd`보다 먼저 매치되는 것을 방지한다.
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

// MARK: - 실행기

/// `command`를 `arguments`와 함께 실행하며 stdio를 상속받는다. 종료를 기다린다.
/// 실행파일이 없거나 리턴 코드가 0이 아닐 때 `ShellError`를 던진다.
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

/// `command`를 `arguments`와 함께 백그라운드 실행하고 `Process` 핸들을 반환한다.
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
            // `cmd.exe /c` 를 통해 실행한다. PowerShell 의존성을 제거하기 위해
            // 기존 pwsh `&` 래퍼 대신 cmd.exe 를 사용한다.
            //
            // Foundation Process 가 Windows 에서 인자에 공백이 있으면 자동으로
            // 큰따옴표로 감싸고 내부 `"` 는 `\"` 로 escape 한다. cmd.exe 는
            // backslash-escape 를 모르므로 우리가 추가로 quoting 하지 말고
            // 인자를 분리해서 넘긴다. 결과 명령행은
            //   cmd /c "C:\Path with space\npm.cmd" arg1 arg2
            // 형태가 되고, cmd /c 의 "2개의 따옴표 + 사이가 실행파일" 규칙으로
            // 따옴표가 보존돼 정확히 실행된다.
            guard let cmdURL = findCmdExe() else { throw ShellError.shellUnavailable }
            process.executableURL = cmdURL
            process.arguments = ["/c", url.path] + arguments
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
        // PowerShell 의존성을 제거하기 위해 cmd.exe /c 를 사용한다.
        // 사용자가 config 에 넣은 commandLine 은 cmd 문법 (`&&`, `|`, `%VAR%`,
        // `>` 등) 을 기대하는 경우가 일반적이므로 그 의미를 보존한다.
        //
        // commandLine 을 하나의 인자로 그대로 넘긴다 — Foundation Process 는
        // 공백이 있을 때 큰따옴표로 감싸 `cmd /c "npm run dev"` 형태가 되고,
        // cmd /c 는 외곽 따옴표를 벗겨 `npm run dev` 를 실행한다. (직접 `\"...\"`
        // 로 감싸면 Foundation 이 내부 따옴표를 `\"` 로 escape 해 cmd 가
        // 명령 자체를 찾지 못한다 — 그 경로의 회귀 방지.)
        guard let shellURL = findCmdExe() else { throw ShellError.shellUnavailable }
        process.executableURL = shellURL
        process.arguments = ["/c", commandLine]
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

#if os(Windows)
    /// `cmd.exe` 를 PATH 보다 우선해 시스템 디렉터리에서 정확히 찾는다.
    /// PATH 가 비정상이거나 동명 셰어가 있는 환경에서도 안정적.
    internal func findCmdExe() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let root = env["SystemRoot"] ?? env["WINDIR"] ?? "C:\\Windows"
        let candidate = URL(fileURLWithPath: root)
            .appendingPathComponent("System32")
            .appendingPathComponent("cmd.exe")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return findExecutable(named: "cmd")
    }
#endif
