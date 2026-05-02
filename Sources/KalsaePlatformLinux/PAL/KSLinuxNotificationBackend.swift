#if os(Linux)
    internal import Glibc
    public import KalsaeCore
    internal import Foundation

    /// Linux implementation of `KSNotificationBackend` using `notify-send`.
    ///
    /// `notify-send` is shipped with `libnotify-bin` (Debian/Ubuntu) and
    /// equivalent packages on other distros. It sends a notification via
    /// the org.freedesktop.Notifications DBus interface without requiring
    /// a compiled C binding.
    ///
    /// Limitations:
    /// - `cancel(id:)` is a no-op because `notify-send` does not expose a
    ///   reliable cancel path across processes.
    /// - `requestPermission()` always returns `true` (Linux does not gate
    ///   notifications behind a user permission dialog).
    public struct KSLinuxNotificationBackend: KSNotificationBackend, Sendable {
        public init() {}

        public func requestPermission() async -> Bool { true }

        public func post(_ notification: KSNotification) async throws(KSError) {
            var args: [String] = []

            // Urgency: map `sound` field to critical when "critical"; otherwise normal.
            if let sound = notification.sound, sound.lowercased() == "critical" {
                args += ["--urgency=critical"]
            } else {
                args += ["--urgency=normal"]
            }

            // Icon path if provided.
            if let icon = notification.iconPath, !icon.isEmpty {
                args += ["--icon=\(icon)"]
            }

            // Hint: use transient so notifications don't pile up in the log.
            args += ["--hint=boolean:transient:true"]

            // Title (required by notify-send).
            args.append(notification.title)

            // Body (optional).
            if let body = notification.body, !body.isEmpty {
                args.append(body)
            }

            let ok = await runProcess("notify-send", args: args)
            if !ok {
                throw KSError(
                    code: .ioFailed,
                    message: "KSLinuxNotificationBackend: notify-send failed for \"\(notification.title)\"")
            }
        }

        public func cancel(id: String) async {
            // notify-send has no stable cancel API; no-op.
        }
    }

    // MARK: - Process helper (reuse the pattern from KSLinuxShellBackend)

    private func runProcess(_ executable: String, args: [String]) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [executable] + args
        // Suppress stdout/stderr so the notification doesn't leak to the console.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
#endif
