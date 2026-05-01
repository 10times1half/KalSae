#if os(Linux)
public import KalsaeCore
public import Foundation

/// Linux implementation of `KSShellBackend` using `xdg-open` and `gio`.
public struct KSLinuxShellBackend: KSShellBackend, Sendable {
    public init() {}

    public func openExternal(_ url: URL) async throws(KSError) {
        try await xdgOpen(url.absoluteString)
    }

    public func showItemInFolder(_ url: URL) async throws(KSError) {
        // For files, open the parent directory; for directories, open directly.
        var isDir: ObjCBool = false
        let path = url.path
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let target: URL
        if exists && !isDir.boolValue {
            target = url.deletingLastPathComponent()
        } else {
            target = url
        }
        try await xdgOpen(target.absoluteString)
    }

    public func moveToTrash(_ url: URL) async throws(KSError) {
        let result = await runProcess("/usr/bin/gio", args: ["trash", url.path])
        if !result {
            // Fallback: try `gio` from PATH
            let result2 = await runProcess("gio", args: ["trash", url.path])
            if !result2 {
                throw KSError(code: .io,
                              message: "moveToTrash: gio trash failed for \(url.path)")
            }
        }
    }
}

// MARK: - Helpers

private func xdgOpen(_ arg: String) async throws(KSError) {
    let success = await runProcess("xdg-open", args: [arg])
    if !success {
        throw KSError(code: .io,
                      message: "openExternal: xdg-open failed for \(arg)")
    }
}

/// Runs an external process, returns `true` if exit code is 0.
/// Searches PATH when `executable` is not an absolute path.
private func runProcess(_ executable: String, args: [String]) async -> Bool {
    let task = Process()
    if executable.hasPrefix("/") {
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
    } else {
        // Resolve via /usr/bin/env for PATH lookup
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [executable] + args
    }
    return _launch(task)
}

private func _launch(_ task: Process) -> Bool {
    do {
        try task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    } catch {
        return false
    }
}
#endif
