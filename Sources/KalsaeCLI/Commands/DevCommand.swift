import ArgumentParser
import Foundation
import KalsaeCLICore
import KalsaeCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if os(Windows)
    import WinSDK
#endif

/// `Kalsae dev` — 개발 모드로 프로젝트를 빌드하고 실행한다.
struct DevCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev",
        abstract: "Build and run the project in development mode."
    )

    @Option(
        name: .shortAndLong, help: "Executable target to run (required when Package.swift has multiple executables).")
    var target: String? = nil

    @Option(
        name: [.customShort("j"), .long],
        help: "Maximum number of parallel jobs forwarded to swift run (default: CPU count).")
    var jobs: Int? = nil

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

    func validate() throws {
        if let jobs, jobs < 1 {
            throw ValidationError("--jobs must be a positive integer (got \(jobs)).")
        }
    }

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

        // `swift run` 이 만들 EXE 옆에 WebView2Loader.dll 을 미리 배치한다.
        // 그렇지 않으면 LoadLibraryW 가 실패해
        // CreateCoreWebView2EnvironmentWithOptions 가 0x8007007E 를 반환한다.
        do {
            try KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: "debug")
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
                #if os(Windows)
                    // `Process.terminate()` 는 Win32 `TerminateProcess` 를
                    // 자식(예: `pwsh`/`cmd.exe`) 에게만 보내므로 손자
                    // `node.exe` 가 살아남아 PowerShell 콘솔 핸들을 계속
                    // 점유한다. `taskkill /F /T` 로 프로세스 트리 전체를
                    // 종료해 PowerShell 이 즉시 프롬프트로 복귀하도록 한다.
                    let pid = devProcess.processIdentifier
                    _ = try? shell(
                        command: "taskkill",
                        arguments: ["/F", "/T", "/PID", String(pid)])
                #else
                    devProcess.terminate()
                #endif
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
        // `-j` 는 swift run 의 underlying build 에 전달되므로 `--` 구분자
        // **앞** 에 놓는다. (`--` 뒤는 애플 자체 인자로 전달됨.)
        if let jobs { args += ["-j", "\(jobs)"] }
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
            // Win32 `ShellExecuteW` 가 PATH 의존성 없이 기본 브라우저(또는
            // 등록된 URL 핸들러)를 직접 띄운다. PowerShell `Start-Process`
            // 의존성을 제거.
            //
            // ShellExecuteW 는 성공 시 > 32 인 HINSTANCE 를 반환한다.
            let rawHandle: Int = url.withCString(encodedAs: UTF16.self) { wURL in
                "open".withCString(encodedAs: UTF16.self) { wVerb in
                    let h = ShellExecuteW(
                        nil, wVerb, wURL, nil, nil, Int32(SW_SHOWNORMAL))
                    return Int(bitPattern: UnsafeRawPointer(h))
                }
            }
            if rawHandle <= 32 {
                print("⚠  Failed to open browser (ShellExecuteW returned \(rawHandle)).")
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
