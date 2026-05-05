import ArgumentParser
import Foundation
import KalsaeCLICore
/// `Kalsae dev` — 개발 모드로 프로젝트를 빌드하고 실행한다.
import KalsaeCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
struct DevCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev",
        abstract: "Build and run the project in development mode."
    )

    @Option(
        name: .shortAndLong, help: "Executable target to run (required when Package.swift has multiple executables).")
    var target: String? = nil

    @Option(
        name: .long,
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

    @Option(
        name: .long,
        help: "Minimum milliseconds to wait between watch-mode restarts (debounces rapid file changes).")
    var debounce: Int = 200

    @Flag(
        name: .long,
        help: "Open the dev server URL in the default browser once it is reachable.")
    var browser: Bool = false

    @Option(
        name: .long,
        help:
            "Arguments to pass to the application after 'swift run', shell-quoted (e.g. --app-args \"--debug --port 8080\")."
    )
    var appArgs: String? = nil

    @Option(
        name: .long,
        help: "Override build.devServerURL (Wails: -frontenddevserverurl).")
    var frontendDevServerURL: String? = nil

    @Option(
        name: .long,
        help: "Seconds to wait for the dev server to become reachable (default: 20).")
    var devServerTimeout: Double = 20

    @Flag(
        name: .long, inversion: .prefixedNo,
        help:
            "Set KALSAE_DEV_RELOAD=1 in the launched app's environment so the host can opt into live asset reload. Use --no-reload to disable. (default: --reload)"
    )
    var reload: Bool = true

    @Flag(
        name: .long, inversion: .prefixedNo,
        help:
            "Automatically fetch the WebView2 SDK into the Kalsae checkout when missing (Windows only)."
    )
    var autoFetchWebView2: Bool = true

    @Option(
        name: .long,
        help: "WebView2 SDK version to fetch when auto-fetching (default: latest).")
    var webview2SdkVersion: String = "latest"

    func run() throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)

        // Windows: `swift run` 이 CKalsaeWV2 를 컴파일하기 전에
        // Kalsae 체크아웃의 Vendor/WebView2 를 채워둔다.
        do {
            try KSWebView2Provisioner.ensure(
                cwd: cwd,
                autoFetch: autoFetchWebView2,
                sdkVersion: webview2SdkVersion)
        } catch let error as ShellError {
            throw ValidationError(error.description)
        }

        let configURL = resolveConfigURLIfPresent(cwd: cwd, fm: fm)
        let appConfig = try loadConfigIfPresent(configURL)
        let plan = KSDevPlan.make(
            config: appConfig,
            skipDevCommand: skipDevCommand,
            noWaitDevServer: noWaitDevServer,
            devServerURLOverride: frontendDevServerURL)

        var devProcess: Process? = nil
        if let raw = plan.devCommand {
            print("🌐  Starting dev server command: \(raw)")
            devProcess = try spawn(commandLine: raw, in: cwd.path)
        }

        defer {
            if let devProcess,
                devProcess.isRunning
            {
                devProcess.terminate()
            }
        }

        if plan.shouldWaitForDevServer,
            let url = plan.devServerURL
        {
            try waitForDevServer(urlString: url, timeoutSeconds: devServerTimeout)
        }

        if browser, let url = plan.devServerURL, Self.isRemoteURL(url) {
            openInBrowser(url)
        }

        var args = ["run"]
        if let t = target { args += [t] }
        let extraAppArgs = Self.parseShellArgs(appArgs)
        if !extraAppArgs.isEmpty {
            args.append("--")
            args += extraAppArgs
        }
        print("▶  swift \(args.joined(separator: " "))")

        // KALSAE_DEV_RELOAD: dev 라이브 리로드 hint. 호스트(KSApp)는 이 env var이
        // "1"이면 frontendDist watcher를 켜고 변경 시 webview reload를 트리거할 수
        // 있다 (host-side wiring은 별도 PR 예정). `--no-reload`로 끌 수 있다.
        let extraEnv: [String: String] = ["KALSAE_DEV_RELOAD": reload ? "1" : "0"]

        if watch {
            try runWatchedSwiftProcess(args: args, cwd: cwd, environment: extraEnv)
        } else {
            try shell(command: "swift", arguments: args, environment: extraEnv)
        }
    }

    private func resolveConfigURLIfPresent(cwd: URL, fm: FileManager) -> URL? {
        if let config {
            return URL(fileURLWithPath: config, relativeTo: cwd)
        }
        return KSConfigLocator.find(cwd: cwd, fm: fm)
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

    private func runWatchedSwiftProcess(
        args: [String], cwd: URL, environment: [String: String]? = nil
    ) throws {
        if watchInterval <= 0 {
            throw ValidationError("--watch-interval must be greater than 0.")
        }
        if debounce < 0 {
            throw ValidationError("--debounce must be >= 0.")
        }

        let fm = FileManager.default
        var fingerprint = watchFingerprint(cwd: cwd, fm: fm)
        var process = try spawn(
            command: "swift", arguments: args, in: cwd.path, environment: environment)
        print("👀  Watch mode enabled (interval: \(watchInterval)s, debounce: \(debounce)ms)")
        var lastRestart: Date = .distantPast

        while true {
            Thread.sleep(forTimeInterval: watchInterval)

            let nextFingerprint = watchFingerprint(cwd: cwd, fm: fm)
            if nextFingerprint > fingerprint {
                let now = Date()
                let elapsedMs = now.timeIntervalSince(lastRestart) * 1000.0
                if elapsedMs < Double(debounce) {
                    continue
                }
                fingerprint = nextFingerprint
                lastRestart = now
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                }
                print("♻️  Changes detected. Restarting swift run...")
                process = try spawn(
                    command: "swift", arguments: args, in: cwd.path,
                    environment: environment)
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
                    let mtime =
                        (try? child.resourceValues(
                            forKeys: [.contentModificationDateKey]))?.contentModificationDate
                        ?? .distantPast
                    if mtime > latest { latest = mtime }
                }
            } else {
                let mtime =
                    (try? url.resourceValues(
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
                (200..<500).contains(http.statusCode)
            {
                result.ok = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        task.cancel()
        return result.ok
    }

    // MARK: - Wails-호환 헬퍼

    /// `http://`/`https://` 인 경우에만 원격으로 본다 (`about:blank` 등은 제외).
    static func isRemoteURL(_ text: String?) -> Bool {
        guard let text,
            let u = URL(string: text),
            let scheme = u.scheme?.lowercased()
        else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// 셸 스타일 인자 분할. 큰따옴표/작은따옴표를 그룹으로 인식하고
    /// 따옴표 내부 공백은 그대로 유지한다. 매우 단순하지만
    /// `--app-args` 일반 사용 케이스에는 충분하다.
    static func parseShellArgs(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        var out: [String] = []
        var current = ""
        var quote: Character? = nil
        for ch in raw {
            if let q = quote {
                if ch == q {
                    quote = nil
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch.isWhitespace {
                if !current.isEmpty {
                    out.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// 기본 브라우저로 URL 열기. 실패는 경고만 출력하고 무시.
    private func openInBrowser(_ url: String) {
        #if os(Windows)
            // PowerShell `Start-Process` 가 가장 확실하다. cmd `start` 는 첫
            // 인자를 윈도우 타이틀로 해석할 수 있어 회피한다.
            do {
                try shell(command: "powershell", arguments: ["-NoProfile", "-Command", "Start-Process", "'\(url)'"])
            } catch {
                print("⚠  Failed to open browser: \(error)")
            }
        #elseif os(macOS)
            do { try shell(command: "open", arguments: [url]) } catch {
                print("⚠  Failed to open browser: \(error)")
            }
        #else
            do { try shell(command: "xdg-open", arguments: [url]) } catch {
                print("⚠  Failed to open browser: \(error)")
            }
        #endif
    }
}
