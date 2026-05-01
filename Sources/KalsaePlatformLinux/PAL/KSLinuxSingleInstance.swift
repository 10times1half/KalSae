#if os(Linux)
internal import Glibc
public import KalsaeCore
public import Foundation

/// Single-instance helper for Linux applications.
///
/// The primary instance creates a Unix-domain socket at
/// `$XDG_RUNTIME_DIR/<identifier>.sock` (or a fallback temp-dir path).
///
/// Subsequent instances connect to the socket, write a newline-delimited
/// list of their command-line arguments, and exit. The primary reads
/// the payload and calls `onSecondInstance`.
///
/// Socket I/O is done in a detached background `Task` so it never
/// blocks the GTK main thread.
public enum KSLinuxSingleInstance {

    public enum Outcome: Sendable {
        /// This process is the primary instance. Continue normal startup.
        case primary
        /// Another instance is already running; arguments were forwarded.
        /// Caller should exit cleanly.
        case relayed
    }

    /// Attempts to acquire single-instance ownership.
    ///
    /// - Parameters:
    ///   - identifier: Stable application identifier.
    ///   - args: Arguments to relay. Defaults to `CommandLine.arguments`.
    ///   - onSecondInstance: Called on the primary when a relay arrives.
    ///     Always invoked on the main actor.
    /// - Returns: `.primary` or `.relayed`.
    public static func acquire(
        identifier: String,
        args: [String] = CommandLine.arguments,
        onSecondInstance: @escaping @MainActor ([String]) -> Void
    ) -> Outcome {
        let path = socketPath(identifier: identifier)

        // Try to connect to an already-running primary.
        if tryRelay(args: args, socketPath: path) {
            return .relayed
        }

        // We are the primary: start listening.
        startListening(socketPath: path, onSecondInstance: onSecondInstance)
        return .primary
    }

    // MARK: - Helpers

    private static func socketPath(identifier: String) -> String {
        let runtime = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"] ?? ""
        let dir = runtime.isEmpty
            ? NSTemporaryDirectory()
            : runtime
        return (dir as NSString).appendingPathComponent(
            "\(identifier).single-instance.sock")
    }

    /// Attempts to relay `args` to an existing primary.
    /// Returns `true` when the relay succeeded.
    private static func tryRelay(args: [String], socketPath: String) -> Bool {
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.count < MemoryLayout.size(ofValue: addr.sun_path) - 1 else {
            return false
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            socketPath.withCString { src in
                _ = strncpy(
                    buf.baseAddress!.assumingMemoryBound(to: CChar.self),
                    src,
                    buf.count - 1)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        // Write args as newline-separated UTF-8, terminated by a single "\0".
        let payload = args.joined(separator: "\n") + "\n\0"
        _ = payload.withCString { ptr in
            send(fd, ptr, strlen(ptr), 0)
        }
        return true
    }

    /// Starts listening on `socketPath` in a background task.
    /// Incoming connections deliver relay payloads; `onSecondInstance` is
    /// dispatched to the main actor for each.
    private static func startListening(
        socketPath: String,
        onSecondInstance: @escaping @MainActor ([String]) -> Void
    ) {
        // Remove stale socket file from a previous crash.
        _ = unlink(socketPath)

        let listenFd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        guard listenFd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutableBytes(of: &addr.sun_path) { buf in
                _ = strncpy(
                    buf.baseAddress!.assumingMemoryBound(to: CChar.self),
                    src,
                    buf.count - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(listenFd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { close(listenFd); return }
        guard listen(listenFd, 5) == 0 else { close(listenFd); return }

        Task.detached {
            await acceptLoop(listenFd: listenFd, onSecondInstance: onSecondInstance)
        }
    }

    private static func acceptLoop(
        listenFd: Int32,
        onSecondInstance: @escaping @MainActor ([String]) -> Void
    ) async {
        while true {
            let clientFd = accept(listenFd, nil, nil)
            guard clientFd >= 0 else { continue }

            Task.detached {
                let args = readArgs(from: clientFd)
                close(clientFd)
                if !args.isEmpty {
                    await MainActor.run { onSecondInstance(args) }
                }
            }
        }
    }

    private static func readArgs(from fd: Int32) -> [String] {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[..<n])
            // Stop at NUL terminator.
            if chunk[..<n].contains(0) { break }
        }
        // Decode and strip NUL.
        guard let text = String(data: buffer, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
#endif
