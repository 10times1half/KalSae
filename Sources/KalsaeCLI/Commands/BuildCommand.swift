import ArgumentParser
import Foundation
import KalsaeCLICore
import KalsaeCore

/// `kalsae build` — 릴리스 (또는 `--debug`일 때는 디버그) 옵션으로 프로젝트를 빌드한다.
struct BuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the project for release."
    )

    @Flag(name: .shortAndLong, help: "Build in debug configuration instead of release.")
    var debug: Bool = false

    @Option(name: .shortAndLong, help: "Executable target to build (optional).")
    var target: String? = nil

    @Flag(name: .long, help: "Produce a redistributable package after building.")
    var package: Bool = false

    @Option(name: .long,
            help: "WebView2 runtime distribution policy: evergreen | fixed | auto.")
    var webview2: String = "evergreen"

    @Option(name: .long,
            help: "Target architecture for the package: x64 | arm64 | x86.")
    var arch: String = "x64"

    @Option(name: .long,
            help: "Path to MicrosoftEdgeWebview2Setup.exe (Evergreen bootstrapper).")
    var bootstrapper: String? = nil

    @Option(name: .long,
            help: "Override path to Kalsae.json (default: ./Kalsae.json or ./kalsae.json).")
    var config: String? = nil

    @Option(name: .long, help: "Override frontend dist directory.")
    var dist: String? = nil

    @Option(name: .long, help: "Override icon path (.ico).")
    var icon: String? = nil

    @Flag(name: .long, help: "Produce a portable .zip alongside the package directory.")
    var zip: Bool = false

    @Option(name: .long, help: "Override package output directory.")
    var output: String? = nil

    @Flag(name: .long, help: "Allow build to continue when frontend dist is missing or empty.")
    var allowMissingDist: Bool = false

    @Flag(name: .long, inversion: .prefixedNo,
          help: "Sync frontend dist into Sources/<target>/Resources before swift build.")
    var syncResources: Bool = true

    @Flag(name: .long, inversion: .prefixedNo,
          help: "Automatically run Scripts/fetch-webview2.ps1 when WebView2 SDK is missing (Windows only).")
    var autoFetchWebView2: Bool = true

    @Option(name: .long, help: "WebView2 SDK version to fetch when auto-fetching (default: latest).")
    var webview2SdkVersion: String = "latest"

    func run() throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let configURL = try resolveConfigURL(cwd: cwd, fm: fm)
        let config = try loadConfig(configURL: configURL)

        try runFrontendBuildIfNeeded(config: config, cwd: cwd)
        try validateFrontendDist(config: config, configURL: configURL, cwd: cwd, fm: fm)
        try syncFrontendResourcesIfNeeded(config: config, configURL: configURL, cwd: cwd, fm: fm)
        try validateWebView2Preconditions(cwd: cwd, fm: fm)

        let configuration = debug ? "debug" : "release"
        let args = KSBuildPlan.swiftBuildArguments(debug: debug, target: target)
        print("🔨  swift \(args.joined(separator: " "))")
        try shell(command: "swift", arguments: args)
        print("✔  Build complete (\(configuration))")

        if package {
            try runPackage(configuration: configuration, configURL: configURL, config: config)
        }
    }

    private func runPackage(configuration: String, configURL: URL, config: KSConfig) throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let info = parseAppInfo(config: config)

        guard let policy = KSPackager.WebView2Policy(rawValue: webview2.lowercased()) else {
            throw ValidationError("--webview2 must be one of: evergreen | fixed | auto")
        }
        guard let archEnum = KSPackager.Architecture(rawValue: arch.lowercased()) else {
            throw ValidationError("--arch must be one of: x64 | arm64 | x86")
        }

        let buildDir = cwd.appendingPathComponent(".build/\(configuration)")
        let exeURL = buildDir.appendingPathComponent("\(info.executableName).exe")
        guard fm.fileExists(atPath: exeURL.path) else {
            throw ValidationError("Built executable not found at \(exeURL.path). Did the build succeed?")
        }

        let distURL: URL? = {
            if let d = dist {
                return URL(fileURLWithPath: d, relativeTo: cwd)
            }
            let candidate = configURL.deletingLastPathComponent()
                .appendingPathComponent(info.frontendDist)
            return fm.fileExists(atPath: candidate.path) ? candidate : nil
        }()

        let vendorRoot: URL? = {
            let r = cwd.appendingPathComponent("Vendor/WebView2/runtimes")
                .appendingPathComponent(archEnum.vendorRuntimeFolder)
            return fm.fileExists(atPath: r.path) ? r : nil
        }()

        let outputURL: URL = {
            if let o = output {
                return URL(fileURLWithPath: o, relativeTo: cwd)
            }
            return cwd.appendingPathComponent(
                "dist/\(info.appName)-\(info.version)-\(archEnum.rawValue)")
        }()

        let opts = KSPackager.Options(
            projectRoot: cwd,
            executablePath: exeURL,
            configPath: configURL,
            frontendDist: distURL,
            output: outputURL,
            appName: info.appName,
            version: info.version,
            identifier: info.identifier,
            architecture: archEnum,
            policy: policy,
            iconPath: icon.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
            vendorRuntimeRoot: vendorRoot,
            bootstrapperPath: bootstrapper.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
            zip: zip)

        print("📦  Packaging \(info.appName) v\(info.version) (\(archEnum.rawValue), \(policy.rawValue))")
        let report = try KSPackager.run(opts)
        print(report.description)
    }

    private struct AppInfo {
        let appName: String
        let version: String
        let identifier: String
        let frontendDist: String
        let executableName: String
    }

    private func resolveConfigURL(cwd: URL, fm: FileManager) throws -> URL {
        if let c = config {
            let url = URL(fileURLWithPath: c, relativeTo: cwd)
            guard fm.fileExists(atPath: url.path) else {
                throw ValidationError("Config file not found at \(url.path).")
            }
            return url
        }
        let upper = cwd.appendingPathComponent("Kalsae.json")
        if fm.fileExists(atPath: upper.path) { return upper }
        let lower = cwd.appendingPathComponent("kalsae.json")
        if fm.fileExists(atPath: lower.path) { return lower }
        throw ValidationError("Could not find Kalsae.json (use --config to override).")
    }

    private func loadConfig(configURL: URL) throws -> KSConfig {
        do {
            return try KSConfigLoader.load(from: configURL)
        } catch {
            throw ValidationError(
                "Failed to load \(configURL.lastPathComponent): \(error)")
        }
    }

    private func runFrontendBuildIfNeeded(config: KSConfig, cwd: URL) throws {
        guard let raw = KSBuildPlan.normalizedCommand(config.build.buildCommand) else {
            return
        }
        print("🧩  Running frontend build command: \(raw)")
        try shell(commandLine: raw, in: cwd.path)
    }

    private func validateFrontendDist(config: KSConfig,
                                      configURL: URL,
                                      cwd: URL,
                                      fm: FileManager) throws {
        let distURL = KSBuildPlan.resolveDistURL(
            config: config,
            configURL: configURL,
            cwd: cwd,
            distOverride: dist)
        do {
            try KSBuildPlan.validateFrontendDist(
                at: distURL,
                allowMissingDist: allowMissingDist,
                fm: fm)
        } catch let error as KSBuildPlanError {
            throw ValidationError(error.description)
        }
    }

    private func webView2LoaderURL(cwd: URL) -> URL {
        cwd
            .appendingPathComponent("Vendor")
            .appendingPathComponent("WebView2")
            .appendingPathComponent("build")
            .appendingPathComponent("native")
            .appendingPathComponent("x64")
            .appendingPathComponent("WebView2LoaderStatic.lib")
    }

    private func validateWebView2Preconditions(cwd: URL, fm: FileManager) throws {
        #if os(Windows)
        let loaderLib = webView2LoaderURL(cwd: cwd)
        if fm.fileExists(atPath: loaderLib.path) { return }

        guard autoFetchWebView2 else {
            throw ValidationError(
                "Missing WebView2 static loader at \(loaderLib.path). Run .\\Scripts\\fetch-webview2.ps1 from the project root, or omit --no-auto-fetch-web-view2 to let kalsae fetch it automatically.")
        }

        let fetchScript = cwd
            .appendingPathComponent("Scripts")
            .appendingPathComponent("fetch-webview2.ps1")
        guard fm.fileExists(atPath: fetchScript.path) else {
            throw ValidationError(
                "WebView2 SDK missing at \(loaderLib.path) and fetch script not found at \(fetchScript.path).")
        }

        let shellName: String
        if findExecutable(named: "pwsh") != nil {
            shellName = "pwsh"
        } else if findExecutable(named: "powershell") != nil {
            shellName = "powershell"
        } else {
            throw ValidationError(
                "WebView2 SDK missing at \(loaderLib.path) and PowerShell was not found in PATH.")
        }

        var args = [
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", fetchScript.path,
            "-ProjectRoot", cwd.path,
        ]
        let ver = webview2SdkVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ver.isEmpty, ver.lowercased() != "latest" {
            args += ["-Version", ver]
        }

        print("⬇️  WebView2 SDK not found — running Scripts/fetch-webview2.ps1...")
        try shell(command: shellName, arguments: args, in: cwd.path)

        guard fm.fileExists(atPath: loaderLib.path) else {
            throw ValidationError(
                "fetch-webview2.ps1 completed but WebView2 static loader is still missing at \(loaderLib.path).")
        }
        #endif
    }

    private func syncFrontendResourcesIfNeeded(config: KSConfig,
                                               configURL: URL,
                                               cwd: URL,
                                               fm: FileManager) throws {
        guard syncResources else { return }

        let distURL = KSBuildPlan.resolveDistURL(
            config: config,
            configURL: configURL,
            cwd: cwd,
            distOverride: dist)

        let executableName = target ?? config.app.name
        let resourcesURL = cwd
            .appendingPathComponent("Sources")
            .appendingPathComponent(executableName)
            .appendingPathComponent("Resources")

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resourcesURL.path, isDirectory: &isDir), isDir.boolValue else {
            return
        }

        let normDist = distURL.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
        let normResources = resourcesURL.standardizedFileURL.path.replacingOccurrences(of: "\\", with: "/")
        if normDist == normResources {
            return
        }

        let preserved = Set(["kalsae.json", "Kalsae.json"])
        let existing = try fm.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        for item in existing where !preserved.contains(item.lastPathComponent) {
            try fm.removeItem(at: item)
        }

        let enumerator = fm.enumerator(
            at: distURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])

        while let src = enumerator?.nextObject() as? URL {
            let relRaw = src.path.replacingOccurrences(of: distURL.path, with: "")
            let rel = relRaw.trimmingCharacters(in: CharacterSet(charactersIn: "\\/"))
            if rel.isEmpty { continue }

            let dst = resourcesURL.appendingPathComponent(rel)

            let values = try src.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try fm.createDirectory(at: dst, withIntermediateDirectories: true)
                continue
            }

            if preserved.contains(dst.lastPathComponent), fm.fileExists(atPath: dst.path) {
                continue
            }

            try fm.createDirectory(
                at: dst.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
        }

        print("📁  Synced frontend dist to \(resourcesURL.path)")
    }

    /// `Kalsae.json`에서 패키징에 필요한 메타데이터만 파싱한다.
    /// `KalsaeCore.KSConfig`를 재사용하여 스키마가 런타임 로더와
    /// 동기화된 상태를 유지한다 — 수동 CLI 파서와
    /// 엔진 관점 사이의 관점 차이가 없다.
    private func parseAppInfo(config: KSConfig) -> AppInfo {
        let exec = target ?? config.app.name
        return AppInfo(
            appName: config.app.name,
            version: config.app.version,
            identifier: config.app.identifier,
            frontendDist: config.build.frontendDist,
            executableName: exec)
    }
}
