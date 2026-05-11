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

    @Option(
        name: [.customShort("j"), .long],
        help: "Maximum number of parallel swift build jobs (default: CPU count).")
    var jobs: Int? = nil

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
        help:
            "Standalone runtime install mode: download | embedBootstrapper | offlineInstaller | fixedVersion | skip."
    )
    var webview2InstallMode: String? = nil

    @Flag(
        name: .long,
        help:
            "Build a standalone-style bundle (single executable target layout). Phase 0/1 compatibility mode currently keeps existing files and options while enabling standalone pipeline flags."
    )
    var standalone: Bool = false

    @Flag(
        name: .long,
        help:
            "When --standalone is on but no PE editor (ResourceHacker / rcedit) is on PATH, fall back to compatibility layout instead of failing the build. Off by default — without this flag, missing PE editors hard-error so a 'standalone' build is never silently identical to a regular build."
    )
    var standaloneAllowFallback: Bool = false

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

    @Flag(
        name: .long, inversion: .prefixedNo,
        help:
            "Automatically run Scripts/fetch-resourcehacker.ps1 when --standalone is on and ResourceHacker is missing (Windows only)."
    )
    var autoFetchResourceHacker: Bool = true

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

    @Option(
        name: .long,
        help:
            "Distribution target (RFC-008): dev | devid | mas | win-store | ios-appstore. Overrides Kalsae.json distribution.target. Default: value from Kalsae.json, or 'dev' if absent."
    )
    var store: String? = nil

    @Option(
        name: .long,
        help: "macOS: codesign identity (e.g. 'Developer ID Application: Name (TEAMID)'). Required with --store devid."
    )
    var codesignIdentity: String? = nil

    @Option(
        name: .long,
        help: "macOS: notarytool keychain profile name (set up via `xcrun notarytool store-credentials`). When provided with --store devid, the bundle is notarized + stapled."
    )
    var notarytoolProfile: String? = nil

    @Option(
        name: .long,
        help: "macOS: path to a custom entitlements.plist. Default: Hardened Runtime preset (cs.allow-jit=true)."
    )
    var entitlements: String? = nil

    @Option(
        name: .long,
        help: "macOS MAS: installer signing identity (e.g. '3rd Party Mac Developer Installer: Name (TEAMID)'). Required with --store mas."
    )
    var installerIdentity: String? = nil

    @Option(
        name: .long,
        help: "macOS MAS: path to embedded.provisionprofile. Required with --store mas."
    )
    var provisionProfile: String? = nil

    @Option(
        name: .long,
        help: "iOS: path to .xcodeproj or .xcworkspace. Required with --store ios-appstore."
    )
    var iosProject: String? = nil

    @Option(
        name: .long,
        help: "iOS: xcodebuild scheme name. Required with --store ios-appstore."
    )
    var iosScheme: String? = nil

    @Option(
        name: .long,
        help: "iOS: export method (app-store-connect | ad-hoc | development). Default: app-store-connect."
    )
    var iosExportMethod: String = "app-store-connect"

    @Option(
        name: .long,
        help: "iOS: App Store Connect API key ID. Combined with --asc-issuer enables altool upload."
    )
    var ascKey: String? = nil

    @Option(
        name: .long,
        help: "iOS: App Store Connect API issuer UUID. Combined with --asc-key enables altool upload."
    )
    var ascIssuer: String? = nil

    @Option(
        name: .long,
        help: "MSIX: AppxManifest Publisher DN (e.g. 'CN=Acme Inc, O=Acme Inc, C=US'). Required with --store win-store. Must match Partner Center registration."
    )
    var publisher: String? = nil

    @Option(
        name: .long,
        help: "MSIX: AppxManifest <PublisherDisplayName>. Default: --publisher CN value or app name."
    )
    var publisherDisplayName: String? = nil

    @Option(
        name: .long,
        help: "MSIX: directory containing manifest Assets (Square150x150Logo.png, Square44x44Logo.png, Wide310x150Logo.png, StoreLogo.png, SplashScreen.png). If absent, placeholders are generated."
    )
    var msixAssets: String? = nil

    @Option(
        name: .long,
        help: "MSIX: signtool template (shell-evaluated, e.g. 'signtool.exe sign /a /fd sha256 {file}'). Omit to skip signing."
    )
    var msixSigntoolCmd: String? = nil

    func validate() throws {
        if let jobs, jobs < 1 {
            throw ValidationError("--jobs must be a positive integer (got \(jobs)).")
        }
        if let mode = webview2InstallMode,
            parseInstallMode(mode) == nil
        {
            throw ValidationError(
                "--webview2-install-mode must be one of: download | embedBootstrapper | offlineInstaller | fixedVersion | skip"
            )
        }
        if let raw = store, KSDistributionTarget.parse(raw) == nil {
            throw ValidationError(
                "--store must be one of: dev | devid | mas | win-store | ios-appstore "
                + "(or full names: developer | developer-id | mac-app-store | "
                + "microsoft-store | ios-app-store). Got '\(raw)'.")
        }
    }

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
        let args = KSBuildPlan.swiftBuildArguments(debug: debug, target: target, jobs: jobs)

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
                    try KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: configuration)
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
                try KSWebView2Provisioner.stageLoaderDLL(cwd: cwd, configuration: configuration)
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
        let target = resolveDistributionTarget(config: config)
        if target != .developer {
            print("📦  Distribution target: \(target.rawValue) (\(target.shortName))")
        }

        // Store-specific packagers (RFC-008 P1~P4) hook here once implemented.
        // For now, all non-`developer` targets fall back to the existing packager
        // with a banner; per-target packaging is a follow-up phase and any user
        // who explicitly passes --store gets a warning that codesign / manifest
        // automation is not wired yet.
        switch target {
        case .developer:
            break
        case .developerID:
            // P1: wired inside runMac via MacOptions.
            break
        case .microsoftStore:
            // P2: wired below after the base Windows package.
            break
        case .macAppStore:
            // P3: wired inside runMac via MacOptions.
            break
        case .iosAppStore:
            #if os(macOS)
                try runPackageIOS(config: config, info: info, cwd: cwd, fm: fm)
                return
            #else
                print(
                    "⚠  --store \(target.shortName): iOS packaging requires macOS host with Xcode. "
                    + "Skipping (the pipeline is otherwise wired and will run on macOS).")
            #endif
        }

        #if os(Windows)
            try runPackageWindows(
                configuration: configuration, configURL: configURL,
                config: config, info: info, cwd: cwd, fm: fm)
            if target == .microsoftStore {
                try runPackageMSIX(
                    config: config, info: info, cwd: cwd, fm: fm)
            }
        #elseif os(macOS)
            try runPackageMacOS(
                configuration: configuration, configURL: configURL,
                info: info, cwd: cwd, fm: fm)
        #else
            print("⚠  Packaging is not supported on this host OS yet. Skipping (use --no-package to silence).")
        #endif
    }

    /// `--store` CLI 플래그가 `Kalsae.json distribution.target` 보다 우선한다.
    /// 양쪽 미지정이면 `.developer`.
    private func resolveDistributionTarget(config: KSConfig) -> KSDistributionTarget {
        if let raw = store, let parsed = KSDistributionTarget.parse(raw) {
            return parsed
        }
        return config.distribution.target
    }

    #if os(Windows)
        private func runPackageWindows(
            configuration: String, configURL: URL, config: KSConfig,
            info: AppInfo, cwd: URL, fm: FileManager
        ) throws {
            guard let policy = KSPackager.WebView2Policy(rawValue: webview2.lowercased()) else {
                throw ValidationError("--webview2 must be one of: evergreen | fixed | auto")
            }
            let installMode = webview2InstallMode.flatMap(parseInstallMode)
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
                    // 사용자가 명시한 --output 은 그대로 존중. standalone 토글 시 같은 폴더를
                    // 공유하면 fingerprint mismatch 로 자동 wipe 후 재생성됨 (Packager.swift §3.1).
                    return URL(fileURLWithPath: o, relativeTo: cwd)
                }
                // standalone 빌드는 일반 빌드와 산출물 내용이 다르므로 (PE 리소스 embed 후
                // 외부 파일 제거) 기본 출력 경로를 분리해 두 빌드를 동시에 보존한다.
                let suffix = standalone ? "-standalone" : ""
                return cwd.appendingPathComponent(
                    "dist/\(info.appName)-\(info.version)-\(archEnum.rawValue)\(suffix)")
            }()

            // standalone 빌드면 ResourceHacker 가용성을 보장 (없으면 자동 fetch).
            // PATH 또는 사용자 캐시(`%LOCALAPPDATA%\Kalsae\Tools\ResourceHacker\`) 에서
            // 찾고, 없으면 Scripts/fetch-resourcehacker.ps1 을 실행한다.
            let resourceHackerPath: URL? = {
                guard standalone else { return nil }
                do {
                    return try KSResourceHackerProvisioner.ensure(
                        cwd: cwd, autoFetch: autoFetchResourceHacker)
                } catch {
                    print("⚠️   ResourceHacker auto-fetch failed: \(error)")
                    return KSResourceHackerProvisioner.locate()
                }
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
                standalone: standalone,
                standaloneAllowFallback: standaloneAllowFallback,
                webView2InstallMode: installMode,
                iconPath: icon.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
                vendorRuntimeRoot: vendorRoot,
                bootstrapperPath: bootstrapper.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
                zip: zip,
                stripSourceMaps: config.build.stripSourceMaps,
                stripExtensions: config.build.stripExtensions,
                resourceHackerPath: resourceHackerPath)

            let modeLabel = installMode?.rawValue ?? "(legacy policy: \(policy.rawValue))"
            print(
                "📦  Packaging \(info.appName) v\(info.version) (\(archEnum.rawValue), mode: \(modeLabel), standalone: \(standalone))"
            )
            let report: KSPackager.Report
            do {
                report = try KSPackager.run(opts)
            } catch let err as KSPackager.StandaloneToolsMissingError {
                // standalone hard-error 를 사용자 친화적인 ValidationError 로 승격.
                throw ValidationError(err.message)
            }
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

        /// Microsoft Store MSIX 패키저 (RFC-008 Phase 2).
        ///
        /// 호출 시점: `runPackageWindows` 가 끝난 직후. 기존 산출물 폴더
        /// (`dist/<App>-<ver>-<arch>/`) 를 **staging 디렉터리로 그대로 사용**한다.
        /// MSIX 매니페스트와 Assets/ 만 추가 작성하고 MakeAppx 를 호출한다.
        private func runPackageMSIX(
            config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager
        ) throws {
            guard let publisher = publisher, !publisher.isEmpty else {
                throw ValidationError(
                    "--store win-store requires --publisher (e.g. "
                    + "'CN=Acme Inc, O=Acme Inc, L=Seoul, C=KR'). The CN must "
                    + "match your Microsoft Partner Center registration.")
            }
            guard let archEnum = KSPackager.MSIXArchitecture(rawValue: arch.lowercased())
                ?? msixArchFallback(arch.lowercased())
            else {
                throw ValidationError(
                    "MSIX --arch must be one of: x64 | x86 | arm64 (got '\(arch)')")
            }

            // staging dir 는 일반 Windows 산출물과 동일 경로.
            let stagingURL: URL = {
                if let o = output {
                    return URL(fileURLWithPath: o, relativeTo: cwd)
                }
                let suffix = standalone ? "-standalone" : ""
                return cwd.appendingPathComponent(
                    "dist/\(info.appName)-\(info.version)-\(arch.lowercased())\(suffix)")
            }()
            guard fm.fileExists(atPath: stagingURL.path) else {
                throw ValidationError(
                    "MSIX staging directory not found: \(stagingURL.path) "
                    + "(expected the base Windows package to exist).")
            }

            // Assets/ 디렉터리 보장 (사용자 제공 우선, 없으면 placeholder 1x1 PNG).
            let assetsDst = stagingURL.appendingPathComponent("Assets")
            try fm.createDirectory(at: assetsDst, withIntermediateDirectories: true)
            try installMSIXAssets(
                userAssets: msixAssets.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
                destination: assetsDst, fm: fm)

            // AppxManifest.xml 작성.
            let deepLinkSchemes = config.deepLink?.schemes ?? []
            let startupID: String? =
                config.autostart != nil
                ? "\(info.identifier).Autostart"
                : nil
            let msixInput = KSPackager.MSIXInput(
                appName: info.appName,
                version: info.version,
                identifier: info.identifier,
                publisher: publisher,
                displayName: info.appName,
                publisherDisplayName: publisherDisplayName ?? deriveCN(from: publisher) ?? info.appName,
                description: nil,
                architecture: archEnum,
                includesWebView2RuntimeDependency: webview2.lowercased() == "evergreen",
                deepLinkSchemes: deepLinkSchemes,
                startupTaskID: startupID,
                startupTaskDisplayName: startupID.map { _ in "\(info.appName) (auto-start)" })
            let manifestURL = stagingURL.appendingPathComponent("AppxManifest.xml")
            let xml = KSPackager.renderAppxManifest(msixInput)
            try xml.write(to: manifestURL, atomically: true, encoding: .utf8)
            print("📝  AppxManifest.xml written (\(xml.count) bytes)")

            // MakeAppx + signtool.
            let msixOut = stagingURL.deletingLastPathComponent()
                .appendingPathComponent("\(info.appName)-\(info.version)-\(arch.lowercased()).msix")
            let plan = KSPackager.planMSIXPipeline(
                .init(
                    stagingDir: stagingURL,
                    outputMSIX: msixOut,
                    signtoolTemplate: msixSigntoolCmd))
            print("📦  MSIX pipeline (\(plan.count) step(s))")
            var warnings: [String] = []
            try KSPackager.executeMSIXSteps(plan, dryRun: dryrun, warnings: &warnings)
            for w in warnings { print("⚠  \(w)") }
            if !dryrun && fm.fileExists(atPath: msixOut.path) {
                print("✅  \(msixOut.path)")
            }
        }

        /// `x86_64` / `x64` 등 별칭을 MSIX arch 로 매핑.
        private func msixArchFallback(_ raw: String) -> KSPackager.MSIXArchitecture? {
            switch raw {
            case "x86_64", "x86-64", "amd64": return .x64
            case "i386", "i686": return .x86
            default: return nil
            }
        }

        /// `"CN=Acme Inc, O=..., C=KR"` → `"Acme Inc"`. 실패 시 nil.
        private func deriveCN(from dn: String) -> String? {
            for raw in dn.split(separator: ",") {
                let part = raw.trimmingCharacters(in: .whitespaces)
                if part.lowercased().hasPrefix("cn=") {
                    return String(part.dropFirst(3))
                }
            }
            return nil
        }

        /// 사용자 Assets 디렉터리가 있으면 복사, 없으면 placeholder PNG 5종 생성.
        private func installMSIXAssets(
            userAssets: URL?, destination: URL, fm: FileManager
        ) throws {
            let required = [
                "Square150x150Logo.png",
                "Square44x44Logo.png",
                "Wide310x150Logo.png",
                "StoreLogo.png",
                "SplashScreen.png",
            ]
            if let src = userAssets, fm.fileExists(atPath: src.path) {
                for name in required {
                    let s = src.appendingPathComponent(name)
                    let d = destination.appendingPathComponent(name)
                    if fm.fileExists(atPath: s.path) {
                        if fm.fileExists(atPath: d.path) { try fm.removeItem(at: d) }
                        try fm.copyItem(at: s, to: d)
                    } else {
                        if !fm.fileExists(atPath: d.path) {
                            try Self.placeholderPNG.write(to: d)
                        }
                        print("⚠  Missing MSIX asset \(name); using placeholder.")
                    }
                }
            } else {
                for name in required {
                    let d = destination.appendingPathComponent(name)
                    if !fm.fileExists(atPath: d.path) {
                        try Self.placeholderPNG.write(to: d)
                    }
                }
                print("⚠  --msix-assets not provided; using placeholder PNGs for all 5 MSIX images. "
                    + "Replace before Partner Center submission.")
            }
        }

        /// 1x1 투명 PNG (transparent), 67 bytes. WACK 는 사이즈를 엄밀히 보지 않지만
        /// Partner Center 제출 전에는 반드시 실제 사이즈로 교체해야 한다.
        private static let placeholderPNG: Data = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82,
        ])
    #endif

    private func parseInstallMode(_ raw: String) -> KSPackager.WebView2InstallMode? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        switch normalized {
        case "download":
            return .download
        case "embedbootstrapper":
            return .embedBootstrapper
        case "offlineinstaller":
            return .offlineInstaller
        case "fixedversion":
            return .fixedVersion
        case "skip":
            return .skip
        default:
            return nil
        }
    }

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
                codesignIdentity: codesignIdentity,
                zip: zip,
                stripSourceMaps: config.build.stripSourceMaps,
                stripExtensions: config.build.stripExtensions,
                distributionTarget: resolveDistributionTarget(config: config),
                notarytoolProfile: notarytoolProfile,
                entitlementsPath: entitlements.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
                signDryRun: dryrun,
                installerSigningIdentity: installerIdentity,
                provisionProfilePath: provisionProfile.map {
                    URL(fileURLWithPath: $0, relativeTo: cwd)
                },
                masEntitlementsInput: resolveDistributionTarget(config: config) == .macAppStore
                    ? makeEntitlementsInput(config: config, target: .macAppStore)
                    : nil)

            print("📦  Packaging \(info.appName).app v\(info.version) (\(archEnum.rawValue))")
            let report = try KSPackager.runMac(opts)
            print(report.description)
        }

        /// iOS App Store IPA 패키징 (RFC-008 P4). macOS + Xcode 필수.
        private func runPackageIOS(
            config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager
        ) throws {
            guard let projectArg = iosProject else {
                throw ValidationError(
                    "--store ios-appstore requires --ios-project <path to .xcodeproj or .xcworkspace>.")
            }
            guard let scheme = iosScheme, !scheme.isEmpty else {
                throw ValidationError(
                    "--store ios-appstore requires --ios-scheme <Xcode scheme name>.")
            }
            guard let teamID = config.distribution.appleTeamID, !teamID.isEmpty else {
                throw ValidationError(
                    "--store ios-appstore requires distribution.appleTeamID in Kalsae.json.")
            }
            guard let method = KSPackager.IOSExportMethod(rawValue: iosExportMethod) else {
                throw ValidationError(
                    "--ios-export-method must be one of: "
                    + "app-store-connect | app-store | ad-hoc | enterprise | development.")
            }

            let projectURL = URL(fileURLWithPath: projectArg, relativeTo: cwd)
            let kind: KSPackager.IOSProjectKind =
                projectArg.hasSuffix(".xcworkspace")
                ? .xcworkspace(projectURL) : .xcodeproj(projectURL)

            let buildBase = cwd.appendingPathComponent(
                "dist/ios-\(info.appName)-\(info.version)")
            try fm.createDirectory(at: buildBase, withIntermediateDirectories: true)
            let archivePath = buildBase.appendingPathComponent("\(info.appName).xcarchive")
            let exportPath = buildBase.appendingPathComponent("export")
            let exportOptionsURL = buildBase.appendingPathComponent("ExportOptions.plist")
            let ipaURL = exportPath.appendingPathComponent("\(info.appName).ipa")

            // exportOptions.plist 생성.
            let plistXML = KSPackager.renderIOSExportOptionsPlist(
                method: method,
                teamID: teamID,
                bundleIdentifier: info.identifier,
                signingStyle: codesignIdentity == nil ? "automatic" : "manual")
            try plistXML.write(to: exportOptionsURL, atomically: true, encoding: .utf8)

            let input = KSPackager.IOSPackagingInput(
                project: kind,
                scheme: scheme,
                archivePath: archivePath,
                exportPath: exportPath,
                exportOptionsPlist: exportOptionsURL,
                ipaOutput: ipaURL,
                teamID: teamID,
                bundleIdentifier: info.identifier,
                exportMethod: method,
                appStoreConnectAPIKeyID: ascKey,
                appStoreConnectAPIIssuerID: ascIssuer,
                codeSignIdentity: codesignIdentity,
                provisioningProfileSpecifier: provisionProfile)

            let steps = KSPackager.planIOSPackagingPipeline(input)
            print(
                "🍎  iOS App Store pipeline (\(steps.count) step(s)) → "
                + ipaURL.path)
            var warnings: [String] = []
            try KSPackager.executeIOSSteps(steps, dryRun: dryrun, warnings: &warnings)
            for w in warnings { print("⚠  \(w)") }
        }
    #endif

    private struct AppInfo {
        let appName: String
        let version: String
        let identifier: String
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
            executableName: exec)
    }
}
