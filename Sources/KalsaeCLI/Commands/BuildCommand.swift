import ArgumentParser
import Foundation
import KalsaeCLICore
/// `kalsae build` — 릴리스 (또는 `--debug`일 때는 디버그) 옵션으로 프로젝트를 빌드한다.
import KalsaeCore

struct BuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the project for release."
    )

    @Flag(name: .shortAndLong, help: "Build in debug configuration instead of release.")
    var debug: Bool = false

    @Option(name: .shortAndLong, help: "Executable target to build (optional).")
    var target: String? = nil

    @Flag(
        name: .long, inversion: .prefixedNo,
        help:
            "Produce a redistributable package after building. Default ON (Wails-compatible). Use --no-package to skip."
    )
    var package: Bool = true

    @Option(
        name: .long,
        help: "WebView2 runtime distribution policy: evergreen | fixed | auto.")
    var webview2: String = "evergreen"

    @Option(
        name: .long,
        help: "Target architecture for the package: x64 | arm64 | x86.")
    var arch: String = "x64"

    @Option(
        name: .long,
        help: "Path to MicrosoftEdgeWebview2Setup.exe (Evergreen bootstrapper).")
    var bootstrapper: String? = nil

    @Option(
        name: .long,
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

    @Flag(
        name: .long, inversion: .prefixedNo,
        help: "Sync frontend dist into Sources/<target>/Resources before swift build.")
    var syncResources: Bool = true

    @Flag(
        name: .long, inversion: .prefixedNo,
        help: "Automatically run Scripts/fetch-webview2.ps1 when WebView2 SDK is missing (Windows only).")
    var autoFetchWebView2: Bool = true

    @Option(name: .long, help: "WebView2 SDK version to fetch when auto-fetching (default: latest).")
    var webview2SdkVersion: String = "latest"

    @Flag(name: .long, help: "Remove .build/ and the package output directory before building.")
    var clean: Bool = false

    @Flag(name: .long, help: "Skip running build.buildCommand (frontend build).")
    var skipFrontend: Bool = false

    @Flag(name: .long, help: "Print the build/package commands without executing them.")
    var dryrun: Bool = false

    @Option(
        name: [.customShort("o"), .long],
        help: "Override the produced executable name (renames the binary in .build/<config>/ after swift build).")
    var exeName: String? = nil

    @Flag(
        name: .long,
        help: "Generate an NSIS installer (.nsi + .exe via makensis) after packaging. Windows-only.")
    var nsis: Bool = false

    @Option(
        name: .long,
        help: "Hint passed to the NSIS template Publisher field (default: app.identifier).")
    var nsisPublisher: String? = nil

    @Option(
        name: .long,
        help:
            "Windows: codesign the packaged executable. Template runs through the host shell. Use {file} as a placeholder for the absolute exe path; if omitted, the path is appended automatically."
    )
    var signtoolCmd: String? = nil

    @Option(
        name: .long,
        help:
            "Windows: codesign the NSIS installer after makensis. Same template syntax as --signtool-cmd. Requires --nsis."
    )
    var nsisSigntoolCmd: String? = nil

    @Flag(
        name: .long, inversion: .prefixedNo,
        help: "Print stage-by-stage wall-clock timings after the build (default ON).")
    var timings: Bool = true

    @Option(
        name: .long,
        help: "Write machine-readable timings JSON to this path (relative to cwd).")
    var timingsJson: String? = nil

    @Flag(
        name: .long, inversion: .prefixedNo,
        help:
            "Run frontend build in parallel with `swift build` (Phase 2). Default ON when `build.buildCommand` is set; ignored otherwise. The first swift build runs against current Resources/; if sync-resources changes any file afterwards, an incremental finalize pass re-bundles them."
    )
    var parallelBuild: Bool = true

    func run() throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        var timer = KSBuildTimings()
        let runStart = ContinuousClock().now

        let configURL = try timer.measure("config") {
            try resolveConfigURL(cwd: cwd, fm: fm)
        }
        let config = try timer.measure("config-load") {
            try loadConfig(configURL: configURL)
        }

        if clean {
            try timer.measure("clean") { try runClean(cwd: cwd, fm: fm) }
        }

        let configuration = debug ? "debug" : "release"
        let args = KSBuildPlan.swiftBuildArguments(debug: debug, target: target)

        let hasFrontendCmd =
            !skipFrontend
            && KSBuildPlan.normalizedCommand(config.build.buildCommand) != nil
        let useParallel = parallelBuild && !dryrun && hasFrontendCmd

        if !useParallel {
            // Serial path (default before Phase 2; preserved for --no-parallel-build,
            // --dryrun, or when no frontend buildCommand is configured).
            try timer.measure("frontend") {
                if !skipFrontend {
                    try runFrontendBuildIfNeeded(config: config, cwd: cwd)
                } else {
                    print("⏭  Skipping frontend build (--skip-frontend)")
                }
            }
            try timer.measure("validate-dist") {
                try validateFrontendDist(config: config, configURL: configURL, cwd: cwd, fm: fm)
            }
            try timer.measure("sync-resources") {
                _ = try syncFrontendResourcesIfNeeded(
                    config: config, configURL: configURL, cwd: cwd, fm: fm)
            }
            try timer.measure("wv2-precheck") {
                try validateWebView2Preconditions(cwd: cwd, fm: fm)
            }

            print("🔨  swift \(args.joined(separator: " "))")
            if dryrun {
                print("(--dryrun) skipping execution")
            } else {
                try timer.measure("swift-build") {
                    try shell(command: "swift", arguments: args)
                }
                print("✔  Build complete (\(configuration))")
                try timer.measure("post-build") {
                    try renameOutputBinaryIfNeeded(
                        config: config, configuration: configuration, cwd: cwd, fm: fm)
                    KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: configuration)
                }
            }
        } else {
            // 병렬 경로 (Phase 2): frontend chain이 동시에 실행되는 동안 `swift build`를 즉시 spawn합니다.
            // 첫 번째 swift build는 *현재* Resources/를 대상으로 수행됩니다 — sync-resources는
            // resource bundle에 대한 쓰기/읽기 경쟁 조건(write/read race)을 방지하기 위해
            // 의도적으로 swift-build 완료 후까지 지연시킵니다.
            // sync 과정에서 파일이 변경된 경우, finalize incremental swift build가
            // 해당 파일들을 artifact에 다시 복사합니다.
            //
            // wv2-precheck는 swift build를 spawn하기 **전에** 반드시 실행되어야 합니다:
            // Windows에서 fresh checkout(또는 `--clean` 이후) 상태에는 WebView2 헤더가 없으며,
            // `Vendor/WebView2/`가 채워질 때까지 C++ shim이 컴파일되지 않습니다.
            // 여기서 캐시된 fast-path는 ~9 ms이므로 병렬성을 저해하지 않습니다.
            try timer.measure("wv2-precheck") {
                try validateWebView2Preconditions(cwd: cwd, fm: fm)
            }

            print("🔨  swift \(args.joined(separator: " ")) (parallel with frontend)")
            let clock = ContinuousClock()
            let swiftSpawnStart = clock.now
            let swiftProc = try spawn(command: "swift", arguments: args)

            var frontendError: (any Error)? = nil
            do {
                try timer.measure("frontend") {
                    try runFrontendBuildIfNeeded(config: config, cwd: cwd)
                }
                try timer.measure("validate-dist") {
                    try validateFrontendDist(
                        config: config, configURL: configURL, cwd: cwd, fm: fm)
                }
            } catch {
                frontendError = error
            }

            // frontend 실패가 발생하더라도 항상 swift-build를 reap합니다.
            // 기록된 duration은 spawn 시점부터 exit까지의 wall-clock 시간(실제 경과 시간)이므로,
            // timing table은 post-frontend 대기 시간 창이 아니라 실제 빌드 비용을 정확하게 반영합니다.
            swiftProc.waitUntilExit()
            timer.record("swift-build", duration: clock.now - swiftSpawnStart)

            if let err = frontendError {
                if swiftProc.terminationStatus != 0 {
                    // 두 분기 모두 실패한 경우, frontend 에러를 primary로 throw하되
                    // swift build 종료 코드도 같이 보고해 사용자가 두 실패를 모두 인지하게 한다.
                    print(
                        "⚠  Both frontend and swift build failed "
                            + "(swift build exit \(swiftProc.terminationStatus)); "
                            + "reporting frontend error.")
                } else {
                    print("⚠  Frontend chain failed; swift build succeeded but is being discarded.")
                }
                throw err
            }
            if swiftProc.terminationStatus != 0 {
                throw ShellError.nonZeroExit(swiftProc.terminationStatus)
            }
            print("✔  Build complete (\(configuration))")

            // Sync after both branches have finished — no race on Resources/.
            let syncChanged = try timer.measure("sync-resources") {
                try syncFrontendResourcesIfNeeded(
                    config: config, configURL: configURL, cwd: cwd, fm: fm)
            }

            if syncChanged {
                // Finalize: SwiftPM incremental rebuild that only re-copies the
                // changed bundle resources. Compilation is already cached.
                print("🔁  Resources changed — running incremental finalize pass…")
                try timer.measure("swift-build-finalize") {
                    try shell(command: "swift", arguments: args)
                }
            }

            try timer.measure("post-build") {
                try renameOutputBinaryIfNeeded(
                    config: config, configuration: configuration, cwd: cwd, fm: fm)
                KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: configuration)
            }
        }

        if package {
            try timer.measure("package") {
                try runPackage(configuration: configuration, configURL: configURL, config: config)
            }
        }

        // 병렬 경로에서는 stage 합산이 실제 wall-clock과 다르므로 명시적으로 기록.
        let runEnd = ContinuousClock().now
        let runDuration = runEnd - runStart
        let runNs =
            UInt64(max(0, runDuration.components.seconds)) * 1_000_000_000
            + UInt64(max(0, runDuration.components.attoseconds / 1_000_000_000))
        timer.wallClockNanoseconds = runNs

        try emitTimings(timer, cwd: cwd)
    }

    private func emitTimings(_ timer: KSBuildTimings, cwd: URL) throws {
        if timings {
            print(timer.summary())
        }
        guard let rel = timingsJson, !rel.isEmpty else { return }
        let url = URL(fileURLWithPath: rel, relativeTo: cwd)
        do {
            let data = try timer.jsonData()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            print("📝  Timings written to \(url.path)")
        } catch {
            // 사용자가 명시적으로 --timings-json 을 지정했으므로 실패는 hard error.
            // 빌드 산출물은 이미 생성된 시점이지만, 사용자에게 보고 실패를 분명히 알려야 한다.
            throw ValidationError(
                "Failed to write timings JSON to \(url.path): \(error)")
        }
    }

    private func runClean(cwd: URL, fm: FileManager) throws {
        let buildDir = cwd.appendingPathComponent(".build")
        let distDir = cwd.appendingPathComponent("dist")
        for url in [buildDir, distDir] {
            guard fm.fileExists(atPath: url.path) else { continue }
            print("🧹  Removing \(url.path)")
            if dryrun { continue }
            try fm.removeItem(at: url)
        }
    }

    /// `--exe-name` 가 지정되면 swift build 산출물(`.build/<config>/<target>.exe`)을
    /// 새 이름으로 복사한다. 원본은 보존(SwiftPM 인크리멘털 빌드 안전).
    private func renameOutputBinaryIfNeeded(
        config: KSConfig, configuration: String, cwd: URL, fm: FileManager
    ) throws {
        guard let exeName, !exeName.isEmpty else { return }
        let info = parseAppInfo(config: config)
        let buildDir = cwd.appendingPathComponent(".build/\(configuration)")
        #if os(Windows)
            let suffix = ".exe"
        #else
            let suffix = ""
        #endif
        let src = buildDir.appendingPathComponent("\(info.executableName)\(suffix)")
        guard fm.fileExists(atPath: src.path) else {
            print("⚠  --exe-name: source binary not found at \(src.path); skipping rename.")
            return
        }
        let dst = buildDir.appendingPathComponent("\(exeName)\(suffix)")
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
        print("📝  Copied \(src.lastPathComponent) → \(dst.lastPathComponent)")
    }

    private func runPackage(configuration: String, configURL: URL, config: KSConfig) throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let info = parseAppInfo(config: config)

        #if os(Windows)
            try runPackageWindows(
                configuration: configuration, configURL: configURL,
                config: config, info: info, cwd: cwd, fm: fm)
        #elseif os(macOS)
            try runPackageMacOS(
                configuration: configuration, configURL: configURL,
                info: info, cwd: cwd, fm: fm)
        #else
            print("⚠  Packaging is not supported on this host OS yet. Skipping (use --no-package to silence).")
        #endif
    }

    #if os(Windows)
        private func runPackageWindows(
            configuration: String, configURL: URL, config: KSConfig,
            info: AppInfo, cwd: URL, fm: FileManager
        ) throws {
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

            // dist 해석은 sync 경로(syncFrontendResourcesIfNeeded)와 동일한 헬퍼를 써
            // --config 가 외부 디렉터리를 가리키더라도 cwd 기준으로 일관되게 처리.
            let distURL: URL? = {
                let resolved = KSBuildPlan.resolveDistURL(
                    config: config, configURL: configURL, cwd: cwd, distOverride: dist)
                return fm.fileExists(atPath: resolved.path) ? resolved : nil
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
                zip: zip,
                stripSourceMaps: config.build.stripSourceMaps,
                stripExtensions: config.build.stripExtensions)

            print("📦  Packaging \(info.appName) v\(info.version) (\(archEnum.rawValue), \(policy.rawValue))")
            let report = try KSPackager.run(opts)
            print(report.description)

            // 패키지된 exe 코드사이닝 hook (P3-2). NSIS 인스톨러보다 먼저 수행해야
            // 인스톨러가 이미 서명된 바이너리를 포장하게 된다.
            if let template = signtoolCmd, !template.isEmpty {
                let pkgExe = outputURL.appendingPathComponent("\(info.appName).exe")
                guard fm.fileExists(atPath: pkgExe.path) else {
                    throw ValidationError(
                        "--signtool-cmd: packaged executable not found at \(pkgExe.path)")
                }
                try KSSigntoolHook.run(
                    template: template, file: pkgExe,
                    label: "signtool (exe)", dryrun: dryrun)
            }

            if nsis {
                // bootstrapper가 함께 패키지된 경우(파일명만 알면 됨)에는 NSIS 인스톨러가
                // WebView2 evergreen 부트스트랩을 silent 호출하도록 한다.
                let bootstrapName: String? =
                    bootstrapper.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? KSPackager.detectBootstrapperFileName(in: outputURL)
                let nsisOpts = KSNSISTemplate.Options(
                    appName: info.appName,
                    version: info.version,
                    identifier: info.identifier,
                    publisher: nsisPublisher ?? info.identifier,
                    architecture: archEnum,
                    sourceDir: outputURL,
                    iconPath: icon.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
                    webView2BootstrapperFileName: bootstrapName)
                print("🛠️   Generating NSIS installer script…")
                let nsisReport = try KSPackager.runNSIS(nsisOpts)
                print(nsisReport.description)

                // NSIS 인스톨러 코드사이닝 hook (P3-2). makensis가 실제로 .exe를
                // 산출했을 때만(installerPath가 nil이 아닐 때) 실행한다.
                if let template = nsisSigntoolCmd, !template.isEmpty {
                    if let installerPath = nsisReport.installerPath {
                        try KSSigntoolHook.run(
                            template: template,
                            file: URL(fileURLWithPath: installerPath),
                            label: "signtool (installer)", dryrun: dryrun)
                    } else {
                        print("⚠  --nsis-signtool-cmd: makensis did not produce an installer; skipping.")
                    }
                }
            } else if nsisSigntoolCmd != nil {
                print("⚠  --nsis-signtool-cmd has no effect without --nsis; skipping.")
            }
        }
    #endif

    #if os(macOS)
        private func runPackageMacOS(
            configuration: String, configURL: URL,
            info: AppInfo, cwd: URL, fm: FileManager
        ) throws {
            // arch 매핑: --arch x64/x86 → x86_64, arm64 → arm64, "universal" 새로 허용.
            let archEnum: KSPackager.MacArchitecture
            switch arch.lowercased() {
            case "arm64": archEnum = .arm64
            case "x64", "x86_64", "x86-64": archEnum = .x86_64
            case "universal": archEnum = .universal
            default:
                throw ValidationError("--arch on macOS must be: arm64 | x86_64 | universal (got '\(arch)')")
            }

            let buildDir = cwd.appendingPathComponent(".build/\(configuration)")
            let exeURL = buildDir.appendingPathComponent(info.executableName)
            guard fm.fileExists(atPath: exeURL.path) else {
                throw ValidationError("Built executable not found at \(exeURL.path). Did the build succeed?")
            }

            // dist 해석은 sync 경로와 동일한 헬퍼를 써 cwd 기준 일관성 보장 (Windows와 동일).
            let distURL: URL? = {
                let resolved = KSBuildPlan.resolveDistURL(
                    config: config, configURL: configURL, cwd: cwd, distOverride: dist)
                return fm.fileExists(atPath: resolved.path) ? resolved : nil
            }()

            let outputURL: URL = {
                if let o = output {
                    return URL(fileURLWithPath: o, relativeTo: cwd)
                }
                return cwd.appendingPathComponent(
                    "dist/\(info.appName)-\(info.version)-\(archEnum.rawValue)")
            }()
            try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

            let opts = KSPackager.MacOptions(
                executablePath: exeURL,
                configPath: configURL,
                frontendDist: distURL,
                output: outputURL,
                appName: info.appName,
                version: info.version,
                identifier: info.identifier,
                architecture: archEnum,
                iconPath: icon.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
                zip: zip,
                stripSourceMaps: config.build.stripSourceMaps,
                stripExtensions: config.build.stripExtensions)

            print("📦  Packaging \(info.appName).app v\(info.version) (\(archEnum.rawValue))")
            let report = try KSPackager.runMac(opts)
            print(report.description)
        }
    #endif

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
        if let found = KSConfigLocator.find(cwd: cwd, fm: fm) {
            return found
        }
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

    private func validateFrontendDist(
        config: KSConfig,
        configURL: URL,
        cwd: URL,
        fm: FileManager
    ) throws {
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

        // 번들 분석 리포트 (bundleReport 옵션이 true일 때)
        if config.build.bundleReport {
            let report = KSBundleAnalyzer.analyze(distURL: distURL)
            print(report.description)
        }
    }

    private func validateWebView2Preconditions(cwd: URL, fm: FileManager) throws {
        #if os(Windows)
            do {
                try KSWebView2Provisioner.ensure(
                    cwd: cwd,
                    autoFetch: autoFetchWebView2,
                    sdkVersion: webview2SdkVersion)
            } catch let error as ShellError {
                throw ValidationError(error.description)
            }
        #endif
    }

    /// Returns `true` when any file was copied or removed. The parallel build
    /// path uses this to decide whether to re-run `swift build` to refresh
    /// the bundled `Resources/` (Phase 2 finalize pass).
    ///
    /// 실제 sync 로직은 `KSResourceSyncManager` 로 분리되어 있다 — 본 함수는
    /// CLI 옵션 (`--sync-resources`, `--target`, `--dist`) 을 dist/Resources URL
    /// 한 쌍으로 해석하고 결과를 사용자 친화적 메시지로 출력하는 책임만 진다.
    @discardableResult
    private func syncFrontendResourcesIfNeeded(
        config: KSConfig,
        configURL: URL,
        cwd: URL,
        fm: FileManager
    ) throws -> Bool {
        guard syncResources else { return false }

        let distURL = KSBuildPlan.resolveDistURL(
            config: config,
            configURL: configURL,
            cwd: cwd,
            distOverride: dist)

        let executableName = target ?? config.app.name
        let resourcesURL =
            cwd
            .appendingPathComponent("Sources")
            .appendingPathComponent(executableName)
            .appendingPathComponent("Resources")

        let report = try KSResourceSyncManager.sync(
            distURL: distURL,
            resourcesURL: resourcesURL,
            fm: fm)

        if let reason = report.skippedReason {
            // 데모처럼 dist 와 Resources/ 가 겹치는 합법적 케이스 — 건너뛴 이유를 안내.
            if reason.contains("overlaps") {
                print(
                    "ℹ  Skipping resource sync: \(reason). "
                        + "Configure `build.frontendDist` to a separate directory to enable sync.")
            }
            return false
        }

        if report.copied == 0 && report.skipped > 0 && report.removed == 0 {
            print("📁  Frontend dist already in sync (\(report.skipped) files unchanged)")
        } else {
            print(
                "📁  Synced frontend dist to \(resourcesURL.path) "
                    + "(\(report.copied) copied, \(report.skipped) unchanged, "
                    + "\(report.removed) removed)")
        }
        if report.failed > 0 {
            print("⚠  Failed to copy \(report.failed) file(s) during sync.")
        }
        return report.didMutate
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
