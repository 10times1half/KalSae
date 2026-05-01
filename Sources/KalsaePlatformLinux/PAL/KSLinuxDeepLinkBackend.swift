#if os(Linux)
internal import Glibc
public import KalsaeCore
public import Foundation

/// Linux implementation of `KSDeepLinkBackend` using the XDG MIME
/// specification and `xdg-mime`.
///
/// For each registered scheme a `.desktop` file is written to
/// `~/.local/share/applications/<identifier>.<scheme>.desktop` declaring:
///
/// ```
/// MimeType=x-scheme-handler/<scheme>;
/// ```
///
/// Then `xdg-mime default` associates the file with the MIME type.
/// `update-desktop-database` is called when available to flush the cache.
public struct KSLinuxDeepLinkBackend: KSDeepLinkBackend, Sendable {
    /// Stable application identifier, e.g. `"dev.example.MyApp"`.
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    // MARK: - KSDeepLinkBackend

    public func register(scheme: String) throws(KSError) {
        let s = try normalized(scheme)
        let mimeType = "x-scheme-handler/\(s)"
        let appDesktopName = "\(identifier).\(s).desktop"
        let desktopFile = applicationsDir().appendingPathComponent(appDesktopName)

        do {
            try FileManager.default.createDirectory(
                at: applicationsDir(), withIntermediateDirectories: true)
        } catch {
            throw KSError(code: .io,
                          message: "KSLinuxDeepLinkBackend: cannot create applications dir: \(error)")
        }

        let exePath = ProcessInfo.processInfo.arguments.first ?? ""
        let content = """
            [Desktop Entry]
            Type=Application
            Name=\(identifier)
            Exec=\(exePath) %u
            MimeType=\(mimeType);
            NoDisplay=true

            """
        do {
            try content.write(to: desktopFile, atomically: true, encoding: .utf8)
        } catch {
            throw KSError(code: .io,
                          message: "KSLinuxDeepLinkBackend: cannot write desktop file: \(error)")
        }

        // Associate MIME type.
        _ = shell("xdg-mime", args: ["default", appDesktopName, mimeType])
        // Flush cache (best-effort).
        _ = shell("update-desktop-database", args: [applicationsDir().path])
    }

    public func unregister(scheme: String) throws(KSError) {
        let s = try normalized(scheme)
        let desktopFile = applicationsDir()
            .appendingPathComponent("\(identifier).\(s).desktop")
        guard FileManager.default.fileExists(atPath: desktopFile.path) else { return }
        do {
            try FileManager.default.removeItem(at: desktopFile)
        } catch {
            throw KSError(code: .io,
                          message: "KSLinuxDeepLinkBackend: cannot remove desktop file: \(error)")
        }
        _ = shell("update-desktop-database", args: [applicationsDir().path])
    }

    public func isRegistered(scheme: String) -> Bool {
        guard let s = try? normalized(scheme) else { return false }
        let mimeType = "x-scheme-handler/\(s)"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let pipe = Pipe()
        task.arguments = ["xdg-mime", "query", "default", mimeType]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expected = "\(identifier).\(s).desktop"
        return output == expected
    }

    public func currentLaunchURLs(forSchemes schemes: [String]) -> [String] {
        let lower = Set(schemes.map { $0.lowercased() })
        return CommandLine.arguments.filter { arg in
            guard let colon = arg.firstIndex(of: ":") else { return false }
            return lower.contains(arg[..<colon].lowercased()) && URL(string: arg) != nil
        }
    }

    public func extractURLs(fromArgs args: [String], forSchemes schemes: [String]) -> [String] {
        let lower = Set(schemes.map { $0.lowercased() })
        return args.filter { a in
            guard let colon = a.firstIndex(of: ":") else { return false }
            let s = a[..<colon].lowercased()
            return lower.contains(s) && URL(string: a) != nil
        }
    }

    // MARK: - Helpers

    private func applicationsDir() -> URL {
        let xdgData = ProcessInfo.processInfo
            .environment["XDG_DATA_HOME"] ?? ""
        let base: URL
        if xdgData.isEmpty {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share")
        } else {
            base = URL(fileURLWithPath: xdgData)
        }
        return base.appendingPathComponent("applications")
    }

    private func normalized(_ scheme: String) throws(KSError) -> String {
        let s = scheme.lowercased()
            .trimmingCharacters(in: .init(charactersIn: "://"))
        guard !s.isEmpty,
              s.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." })
        else {
            throw KSError(code: .configInvalid,
                          message: "KSLinuxDeepLinkBackend: invalid scheme \"\(scheme)\"")
        }
        return s
    }

    @discardableResult
    private func shell(_ cmd: String, args: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [cmd] + args
        task.standardOutput = FileHandle.nullDevice
        task.standardError  = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch { return false }
    }
}
#endif
