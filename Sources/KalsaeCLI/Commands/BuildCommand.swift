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

    func run() throws {
        let configuration = debug ? "debug" : "release"
        var args = ["build", "-c", configuration]
        if let t = target { args += ["--target", t] }
        print("🔨  swift \(args.joined(separator: " "))")
        try shell(command: "swift", arguments: args)
        print("✔  Build complete (\(configuration))")

        if package {
            try runPackage(configuration: configuration)
        }
    }

    private func runPackage(configuration: String) throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)

        let configURL: URL
        if let c = config {
            configURL = URL(fileURLWithPath: c, relativeTo: cwd)
        } else if fm.fileExists(atPath: cwd.appendingPathComponent("Kalsae.json").path) {
            configURL = cwd.appendingPathComponent("Kalsae.json")
        } else if fm.fileExists(atPath: cwd.appendingPathComponent("kalsae.json").path) {
            configURL = cwd.appendingPathComponent("kalsae.json")
        } else {
            throw ValidationError("Could not find Kalsae.json (use --config to override).")
        }
        let info = try parseAppInfo(configURL: configURL)

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

    /// `Kalsae.json`에서 패키징에 필요한 메타데이터만 파싱한다.
    /// `KalsaeCore.KSConfig`를 재사용하여 스키마가 런타임 로더와
    /// 동기화된 상태를 유지한다 — 수동 CLI 파서와
    /// 엔진 관점 사이의 관점 차이가 없다.
    private func parseAppInfo(configURL: URL) throws -> AppInfo {
        let config: KSConfig
        do {
            config = try KSConfigLoader.load(from: configURL)
        } catch {
            // typed throws(KSError) → 단일 catch에 KSError가 바인딩된다.
            throw ValidationError(
                "Failed to load \(configURL.lastPathComponent): \(error)")
        }
        let exec = target ?? config.app.name
        return AppInfo(
            appName: config.app.name,
            version: config.app.version,
            identifier: config.app.identifier,
            frontendDist: config.build.frontendDist,
            executableName: exec)
    }
}
