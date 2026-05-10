#if os(Linux)
    internal import CKalsaeGtk
    internal import Glibc
    public import KalsaeCore
    internal import Foundation

    /// Linux implementation of `KSNotificationBackend`.
    ///
    /// Preferred path: `GtkApplication` + `GNotification` (native, cancellable).
    /// Fallback path: `notify-send` when no active GTK host exists.
    ///
    /// `requestPermission()` always returns `true` (Linux does not gate
    /// notifications behind a user permission dialog).
    public struct KSLinuxNotificationBackend: KSNotificationBackend, Sendable {
        public init() {}

        public func requestPermission() async -> Bool { true }

        public func post(_ notification: KSNotification) async throws(KSError) {
            let nativePosted: Bool = await MainActor.run {
                guard let hostPtr = primaryHostPtr() else { return false }
                let urgent = (notification.sound?.lowercased() == "critical") ? 1 : 0
                return ks_gtk_host_send_notification(
                    hostPtr,
                    notification.id,
                    notification.title,
                    notification.body,
                    notification.iconPath,
                    urgent) != 0
            }
            if nativePosted { return }

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
                    message: "KSLinuxNotificationBackend: native + notify-send both failed for \"\(notification.title)\"")
            }
        }

        public func cancel(id: String) async {
            await MainActor.run {
                guard !id.isEmpty, let hostPtr = primaryHostPtr() else { return }
                ks_gtk_host_withdraw_notification(hostPtr, id)
            }
        }

        @MainActor
        private func primaryHostPtr() -> OpaquePointer? {
            let reg = KSLinuxHandleRegistry.shared
            return reg.allHandles().first
                .flatMap { reg.entry(for: $0) }?
                .host.hostPtr
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
