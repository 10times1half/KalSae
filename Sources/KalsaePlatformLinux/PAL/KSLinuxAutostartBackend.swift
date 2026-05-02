#if os(Linux)
    internal import Glibc
    public import KalsaeCore
    public import Foundation

    /// Linux implementation of `KSAutostartBackend` using the XDG autostart
    /// specification.
    ///
    /// Writes / removes a `.desktop` file in
    /// `$XDG_CONFIG_HOME/autostart/` (default: `~/.config/autostart/`)
    /// pointing at the current executable.
    ///
    /// Reference: https://specifications.freedesktop.org/autostart-spec/latest/
    public struct KSLinuxAutostartBackend: KSAutostartBackend, Sendable {
        /// Stable application identifier, e.g. `"dev.example.MyApp"`.
        /// Used as the `.desktop` file's base name.
        public let identifier: String

        public init(identifier: String) {
            self.identifier = identifier
        }

        public func enable() throws(KSError) {
            let dir = autostartDir()
            do {
                try FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true)
            } catch {
                throw KSError(
                    code: .io,
                    message: "KSLinuxAutostartBackend: cannot create autostart dir: \(error)")
            }

            let exePath = ProcessInfo.processInfo.arguments.first ?? ""
            let content = """
                [Desktop Entry]
                Type=Application
                Name=\(identifier)
                Exec=\(exePath)
                X-GNOME-Autostart-enabled=true
                Hidden=false
                NoDisplay=false

                """

            do {
                try content.write(to: desktopFileURL(), atomically: true, encoding: .utf8)
            } catch {
                throw KSError(
                    code: .io,
                    message: "KSLinuxAutostartBackend: cannot write desktop file: \(error)")
            }
        }

        public func disable() throws(KSError) {
            let url = desktopFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw KSError(
                    code: .io,
                    message: "KSLinuxAutostartBackend: cannot remove desktop file: \(error)")
            }
        }

        public func isEnabled() -> Bool {
            FileManager.default.fileExists(atPath: desktopFileURL().path)
        }

        // MARK: - Helpers

        private func autostartDir() -> URL {
            let xdgConfig =
                ProcessInfo.processInfo
                .environment["XDG_CONFIG_HOME"] ?? ""
            let base: URL
            if xdgConfig.isEmpty {
                base = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".config")
            } else {
                base = URL(fileURLWithPath: xdgConfig)
            }
            return base.appendingPathComponent("autostart")
        }

        private func desktopFileURL() -> URL {
            autostartDir().appendingPathComponent("\(identifier).desktop")
        }
    }
#endif
