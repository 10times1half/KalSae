public import Foundation

// MARK: - Errors

public enum ShellError: Error, CustomStringConvertible {
    case commandNotFound(String)
    case nonZeroExit(Int32)

    public var description: String {
        switch self {
        case .commandNotFound(let cmd): return "'\(cmd)' not found in PATH."
        case .nonZeroExit(let code):    return "Process exited with code \(code)."
        }
    }
}

// MARK: - PATH lookup

/// Returns the full URL of `name` found in the system PATH, or `nil`.
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

// MARK: - Runner

/// Runs `command` with `arguments`, inheriting stdio.  Waits for exit.
/// Throws `ShellError` on missing executable or non-zero exit code.
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
