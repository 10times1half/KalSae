import ArgumentParser
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import KalsaeCLICore
import KalsaeCore

/// `Kalsae dev` — 개발 모드로 프로젝트를 빌드하고 실행한다.
struct DevCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev",
        abstract: "Build and run the project in development mode."
    )

    @Option(name: .shortAndLong, help: "Executable target to run (required when Package.swift has multiple executables).")
    var target: String? = nil

    @Option(name: .long,
            help: "Override path to Kalsae.json (default: ./Kalsae.json or ./kalsae.json when present).")
    var config: String? = nil

    @Flag(name: .long, help: "Do not launch build.devCommand even when configured.")
    var skipDevCommand: Bool = false

    @Flag(name: .long, help: "Skip waiting for build.devServerURL to become reachable.")
    var noWaitDevServer: Bool = false

    @Flag(name: .long, help: "Watch Sources/ and restart swift run on file changes.")
    var watch: Bool = false

    @Option(name: .long, help: "Polling interval in seconds for --watch mode.")
    var watchInterval: Double = 1.0

    func run() throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let configURL = resolveConfigURLIfPresent(cwd: cwd, fm: fm)
        let appConfig = try loadConfigIfPresent(configURL)
        let plan = KSDevPlan.make(
            config: appConfig,
            skipDevCommand: skipDevCommand,
            noWaitDevServer: noWaitDevServer)

        var devProcess: Process? = nil
        if let raw = plan.devCommand {
            print("🌐  Starting dev server command: \(raw)")
            devProcess = try spawn(commandLine: raw, in: cwd.path)
        }

        defer {
            if let devProcess,
               devProcess.isRunning {
                devProcess.terminate()
            }
        }

          if plan.shouldWaitForDevServer,
           let url = plan.devServerURL {
            try waitForDevServer(urlString: url, timeoutSeconds: 20)
        }

        var args = ["run"]
        if let t = target { args += [t] }
        print("▶  swift \(args.joined(separator: " "))")

        if watch {
            try runWatchedSwiftProcess(args: args, cwd: cwd)
        } else {
            try shell(command: "swift", arguments: args)
        }
    }

    private func resolveConfigURLIfPresent(cwd: URL, fm: FileManager) -> URL? {
        if let config {
            return URL(fileURLWithPath: config, relativeTo: cwd)
        }
        let upper = cwd.appendingPathComponent("Kalsae.json")
        if fm.fileExists(atPath: upper.path) { return upper }
        let lower = cwd.appendingPathComponent("kalsae.json")
        if fm.fileExists(atPath: lower.path) { return lower }
        return nil
    }

    private func loadConfigIfPresent(_ configURL: URL?) throws -> KSConfig? {
        guard let configURL else { return nil }
        do {
            return try KSConfigLoader.load(from: configURL)
        } catch {
            throw ValidationError(
                "Failed to load \(configURL.lastPathComponent): \(error)")
        }
    }

    private func waitForDevServer(urlString: String, timeoutSeconds: TimeInterval) throws {
        guard let url = URL(string: urlString) else {
            throw ValidationError("Invalid build.devServerURL: \(urlString)")
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if ping(url: url) {
                print("✅  Dev server is reachable at \(urlString)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw ValidationError(
            "Dev server did not become reachable within \(Int(timeoutSeconds))s: \(urlString)")
    }

    private func runWatchedSwiftProcess(args: [String], cwd: URL) throws {
        if watchInterval <= 0 {
            throw ValidationError("--watch-interval must be greater than 0.")
        }

        let fm = FileManager.default
        var fingerprint = watchFingerprint(cwd: cwd, fm: fm)
        var process = try spawn(command: "swift", arguments: args, in: cwd.path)
        print("👀  Watch mode enabled (interval: \(watchInterval)s)")

        while true {
            Thread.sleep(forTimeInterval: watchInterval)

            let nextFingerprint = watchFingerprint(cwd: cwd, fm: fm)
            if nextFingerprint > fingerprint {
                fingerprint = nextFingerprint
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                print("♻️  Changes detected. Restarting swift run...")
                process = try spawn(command: "swift", arguments: args, in: cwd.path)
                continue
            }

            if !process.isRunning {
                let status = process.terminationStatus
                if status == 0 {
                    return
                }
                throw ValidationError("swift run exited with code \(status).")
            }
        }
    }

    private func watchFingerprint(cwd: URL, fm: FileManager) -> TimeInterval {
        var latest: Date = .distantPast

        let candidates: [URL] = [
            cwd.appendingPathComponent("Sources"),
            cwd.appendingPathComponent("Package.swift"),
            cwd.appendingPathComponent("Kalsae.json"),
            cwd.appendingPathComponent("kalsae.json"),
        ]

        for url in candidates {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let e = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles])
                while let child = e?.nextObject() as? URL {
                    let mtime = (try? child.resourceValues(
                        forKeys: [.contentModificationDateKey]))?.contentModificationDate
                        ?? .distantPast
                    if mtime > latest { latest = mtime }
                }
            } else {
                let mtime = (try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast
                if mtime > latest { latest = mtime }
            }
        }

        return latest.timeIntervalSince1970
    }

    private func ping(url: URL) -> Bool {
        final class PingResult: @unchecked Sendable {
            var ok: Bool = false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0

        let semaphore = DispatchSemaphore(value: 0)
        let result = PingResult()

        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse,
               (200..<500).contains(http.statusCode) {
                result.ok = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        task.cancel()
        return result.ok
    }
}
