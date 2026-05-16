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
        help: "Override path to kalsae.json (default: ./kalsae.json).")
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
            "Automatically download ResourceHacker when --standalone is on and it is missing (Windows only)."
    )
    var autoFetchResourceHacker: Bool = true

    @Flag(name: .long, help: "Remove .build/ and the package output directory before building.")
    var clean: Bool = false

    @Flag(name: .long, help: "Skip running build.buildCommand (frontend build).")
    var skipFrontend: Bool = false

    @Option(
        name: .long,
        help: "Capability/permission validation mode: strict | warn | off (default: warn).")
    var capabilityCheck: String = "warn"

    @Flag(name: .long, help: "Print the build/package commands without executing them.")
    var dryrun: Bool = false

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
            "Distribution target (RFC-008): dev | devid | mas | win-store | ios-appstore. Overrides kalsae.json distribution.target. Default: value from kalsae.json, or 'dev' if absent."
    )
    var store: String? = nil

    @Option(
        name: .long,
        help: "macOS: codesign identity (e.g. 'Developer ID Application: Name (TEAMID)'). Required with --store devid."
    )
    var codesignIdentity: String? = nil

    @Option(
        name: .long,
        help:
            "macOS: notarytool keychain profile name (set up via `xcrun notarytool store-credentials`). When provided with --store devid, the bundle is notarized + stapled."
    )
    var notarytoolProfile: String? = nil

    @Option(
        name: .long,
        help: "macOS: path to a custom entitlements.plist. Default: Hardened Runtime preset (cs.allow-jit=true)."
    )
    var entitlements: String? = nil

    @Option(
        name: .long,
        help:
            "macOS MAS: installer signing identity (e.g. '3rd Party Mac Developer Installer: Name (TEAMID)'). Required with --store mas."
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
        help:
            "MSIX: AppxManifest Publisher DN (e.g. 'CN=Acme Inc, O=Acme Inc, C=US'). Required with --store win-store. Must match Partner Center registration."
    )
    var publisher: String? = nil

    @Option(
        name: .long,
        help: "MSIX: AppxManifest <PublisherDisplayName>. Default: --publisher CN value or app name."
    )
    var publisherDisplayName: String? = nil

    @Option(
        name: .long,
        help:
            "MSIX: directory containing manifest Assets (Square150x150Logo.png, Square44x44Logo.png, Wide310x150Logo.png, StoreLogo.png, SplashScreen.png). If absent, placeholders are generated."
    )
    var msixAssets: String? = nil

    @Option(
        name: .long,
        help:
            "MSIX: signtool template (shell-evaluated, e.g. 'signtool.exe sign /a /fd sha256 {file}'). Omit to skip signing."
    )
    var msixSigntoolCmd: String? = nil

    // MARK: - Android (RFC-007)

    @Flag(
        name: .long,
        help:
            "Emit an Android Gradle project (RFC-007). Skips the host's normal Win/Mac/Linux packager. Requires --android-native-lib pointing at libKalsaePlatformAndroid.so."
    )
    var android: Bool = false

    @Option(
        name: .long,
        help:
            "Android: path to libKalsaePlatformAndroid.so (built via `swift build --swift-sdk aarch64-unknown-linux-android26 -c release`). Required with --android."
    )
    var androidNativeLib: String? = nil

    @Option(
        name: .long,
        help: "Android: applicationId (e.g. 'com.example.myapp'). Default: kalsae.json app.identifier."
    )
    var androidApplicationId: String? = nil

    @Option(
        name: .long,
        help: "Android: integer versionCode (must increase per release). Default: 1.")
    var androidVersionCode: Int = 1

    @Option(
        name: .long,
        help: "Android: minSdk API level (>= 26). Default: 26.")
    var androidMinSdk: Int = 26

    @Option(
        name: .long,
        help: "Android: targetSdk API level (>= minSdk). Default: 35.")
    var androidTargetSdk: Int = 35

    @Option(
        name: .long,
        help: "Android: path to 1024x1024 launcher icon PNG. If absent, a placeholder is used.")
    var androidIcon: String? = nil

    // MARK: - iOS (Phase iOS-Stable §3)

    @Flag(
        name: .long,
        help:
            "Emit an iOS .app bundle (preview-stable). Skips the host's normal Win/Mac/Linux packager. Requires --ios-executable pointing at the iOS-built binary."
    )
    var ios: Bool = false

    @Option(
        name: .long,
        help:
            "iOS: path to the cross-compiled iOS executable (Mach-O). Built via `swift build --triple arm64-apple-ios16.0 -c release --product <YourApp>`. Required with --ios."
    )
    var iosExecutable: String? = nil

    @Option(
        name: .long,
        help: "iOS: CFBundleIdentifier (e.g. 'com.example.myapp'). Default: kalsae.json app.identifier."
    )
    var iosBundleIdentifier: String? = nil

    @Option(
        name: .long,
        help: "iOS: CFBundleVersion (build number, must increase per submission). Default: 1.")
    var iosBundleVersion: String = "1"

    @Option(
        name: .long,
        help: "iOS: MinimumOSVersion (e.g. '16.0'). Default: 16.0.")
    var iosMinOSVersion: String = "16.0"

    @Option(
        name: .long,
        help: "iOS: launcher icon PNG (1024x1024 recommended). Optional.")
    var iosIcon: String? = nil

    // MARK: - Linux (RFC-009)

    @Flag(
        name: .long,
        help:
            "Emit a Linux distribution tree (RFC-009). Skips the host's normal Win/Mac packager. Requires --linux-executable pointing at the Linux ELF binary."
    )
    var linux: Bool = false

    @Option(
        name: .long,
        help:
            "Linux: path to the built Linux ELF executable (e.g. .build/release/MyApp). Required with --linux."
    )
    var linuxExecutable: String? = nil

    @Option(
        name: .long,
        help:
            "Linux: comma-separated formats — any of 'tarball', 'deb', 'appimage'. Default: 'tarball'."
    )
    var linuxFormat: String = "tarball"

    @Option(
        name: .long,
        help: "Linux: target architecture — 'x86_64' or 'aarch64'. Default: x86_64.")
    var linuxArch: String = "x86_64"

    @Option(
        name: .long,
        help: "Linux: launcher icon PNG (512x512 recommended). Optional.")
    var linuxIcon: String? = nil

    @Option(
        name: .long,
        help: "Linux: .deb Maintainer field — 'Name <email@host>'. Required with --linux-format deb.")
    var linuxMaintainer: String? = nil

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

        // 비-ASCII 경로는 SwiftPM(Windows) 가 임시 빌드 산출물을 찾지 못해 깨지므로
        // 명확한 에러로 사전 차단한다. 모든 OS 에서 일관되게 적용.
        do {
            try KSProjectNameValidator.validatePath(cwd, role: "current working directory")
        } catch let e as KSProjectNameValidator.ValidationFailure {
            throw ValidationError(e.description)
        }

        let configURL = try timer.measure("config") {
            try resolveConfigURL(cwd: cwd, fm: fm)
        }
        let config = try timer.measure("config-load") {
            try loadConfig(configURL: configURL)
        }

        try timer.measure("capability-check") {
            try runCapabilityValidation(config: config, cwd: cwd)
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

    private func runPackage(configuration: String, configURL: URL, config: KSConfig) throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let info = parseAppInfo(config: config)

        // RFC-007: --android short-circuits host packagers entirely.
        if android {
            try runPackageAndroid(config: config, info: info, cwd: cwd, fm: fm)
            return
        }

        // Phase iOS-Stable §3: --ios short-circuits host packagers entirely.
        // (별도의 `--store ios-appstore` 는 macOS 호스트의 xcodebuild 파이프라인을
        // 거치는 IPA 생성용으로 유지되며, `--ios` 는 어느 호스트에서나 동작하는
        // 미니멀 .app 번들 emit 를 수행한다.)
        if ios {
            try runPackageIOSAppBundle(config: config, info: info, cwd: cwd, fm: fm)
            return
        }

        // RFC-009: --linux short-circuits host packagers entirely (emit-only, host-OS agnostic).
        if linux {
            try runPackageLinux(config: config, info: info, cwd: cwd, fm: fm)
            return
        }

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

    /// `--store` CLI 플래그가 `kalsae.json distribution.target` 보다 우선한다.
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
            // 찾고, 없으면 angusj.com 에서 직접 zip 을 받아 캐시에 설치한다.
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
            guard
                let archEnum = KSPackager.MSIXArchitecture(rawValue: arch.lowercased())
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
                print(
                    "⚠  --msix-assets not provided; using placeholder PNGs for all 5 MSIX images. "
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
                    "--store ios-appstore requires distribution.appleTeamID in kalsae.json.")
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

    /// Android Gradle 프로젝트 생성 (RFC-007). 호스트 OS 무관 (순수 파일 emit).
    /// 실제 APK 빌드는 호출자가 산출 디렉터리에서 `gradle wrapper` →
    /// `./gradlew assembleRelease` 로 수행한다.
    private func runPackageAndroid(
        config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager
    ) throws {
        guard let libArg = androidNativeLib else {
            throw ValidationError(
                "--android requires --android-native-lib <path to libKalsaePlatformAndroid.so>. "
                    + "Build it first with: "
                    + "swift build --swift-sdk aarch64-unknown-linux-android\(androidMinSdk) "
                    + "-c release --product KalsaePlatformAndroid")
        }
        // Android 는 현재 arm64-v8a 만 지원한다. default(x64) 는 조용히 arm64 로 치환하고,
        // 사용자가 명시적으로 다른 값(`--arch arm64` 이외)을 지정한 경우에만 경고를 띄운다.
        if arch != "arm64" && arch != "x64" {
            print("⚠  --arch \(arch): Android currently supports only 'arm64' (arm64-v8a). Overriding to arm64.")
        }

        let libURL = URL(fileURLWithPath: libArg, relativeTo: cwd)
        let outputDir = output.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
            ?? cwd.appendingPathComponent("dist/android-\(info.appName)-\(info.version)")

        let applicationId = androidApplicationId ?? info.identifier
        let iconURL: URL? = androidIcon.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
        let frontendDistURL: URL? = {
            if let raw = dist, !raw.isEmpty {
                return URL(fileURLWithPath: raw, relativeTo: cwd)
            }
            let fallback = cwd.appendingPathComponent(config.build.frontendDist)
            return fm.fileExists(atPath: fallback.path) ? fallback : nil
        }()
        let deepLinkSchemes = config.deepLink?.schemes ?? []

        let opts = KSPackager.AndroidOptions(
            nativeLibPath: libURL,
            configPath: try resolveConfigURL(cwd: cwd, fm: fm),
            frontendDist: frontendDistURL,
            output: outputDir,
            appName: info.appName,
            version: info.version,
            identifier: applicationId,
            versionCode: androidVersionCode,
            minimumAPILevel: androidMinSdk,
            targetAPILevel: androidTargetSdk,
            architecture: .arm64,
            iconPath: iconURL,
            deepLinkSchemes: deepLinkSchemes)

        print("📦  Packaging \(info.appName) Android Gradle project v\(info.version) → \(outputDir.path)")
        if dryrun {
            print("   (dry-run: skipping file emission)")
            return
        }
        let report = try KSPackager.runAndroid(opts)
        print(report.description)
        print("ℹ  Next steps: cd '\(outputDir.path)' ; gradle wrapper ; ./gradlew assembleRelease")
    }

    /// Phase iOS-Stable §3 — `--ios` 플래그 진입점. 어느 호스트에서나 동작하는
    /// 미니멀 .app 번들 emit. 실제 디바이스 실행/시뮬레이터 설치는 macOS 가 필요.
    private func runPackageIOSAppBundle(
        config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager
    ) throws {
        guard let exeArg = iosExecutable else {
            throw ValidationError(
                "--ios requires --ios-executable <path to iOS Mach-O binary>. "
                    + "Build it first with: "
                    + "swift build --triple arm64-apple-ios\(iosMinOSVersion) "
                    + "-c release --product <YourApp>")
        }
        let arch: KSPackager.IOSArchitecture = {
            switch self.arch {
            case "arm64", "x64": return .arm64
            case "arm64-simulator": return .arm64Simulator
            default:
                print(
                    "⚠  --arch \(self.arch): iOS supports 'arm64' or 'arm64-simulator'. "
                        + "Defaulting to arm64.")
                return .arm64
            }
        }()

        let exeURL = URL(fileURLWithPath: exeArg, relativeTo: cwd)
        let outputDir = output.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
            ?? cwd.appendingPathComponent("dist/ios-\(info.appName)-\(info.version)")

        let identifier = iosBundleIdentifier ?? info.identifier
        let iconURL: URL? = iosIcon.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
        let frontendDistURL: URL? = {
            if let raw = dist, !raw.isEmpty {
                return URL(fileURLWithPath: raw, relativeTo: cwd)
            }
            let fallback = cwd.appendingPathComponent(config.build.frontendDist)
            return fm.fileExists(atPath: fallback.path) ? fallback : nil
        }()
        let deepLinkSchemes = config.deepLink?.schemes ?? []

        let opts = KSPackager.IOSOptions(
            executablePath: exeURL,
            configPath: try resolveConfigURL(cwd: cwd, fm: fm),
            frontendDist: frontendDistURL,
            output: outputDir,
            appName: info.appName,
            version: info.version,
            identifier: identifier,
            bundleVersion: iosBundleVersion,
            minimumOSVersion: iosMinOSVersion,
            architecture: arch,
            iconPath: iconURL,
            deepLinkSchemes: deepLinkSchemes,
            permissions: config.permissions)

        print("📦  Packaging \(info.appName) iOS .app v\(info.version) → \(outputDir.path)")
        if dryrun {
            print("   (dry-run: skipping file emission)")
            return
        }
        let report = try KSPackager.runIOS(opts)
        print(report.description)
        print(
            "ℹ  Next steps: install on a simulator with "
                + "`xcrun simctl install booted '\(report.outputPath)'` "
                + "(macOS + Xcode required).")
    }

    /// RFC-009 — `--linux` 플래그 진입점. 어느 호스트에서나 동작하는 emit-only
    /// 파이프라인. 실제 `.deb` / `.AppImage` 산출은 Linux 호스트의 외부 도구
    /// (`dpkg-deb`, `appimagetool`) 가 마무리한다.
    private func runPackageLinux(
        config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager
    ) throws {
        guard let exeArg = linuxExecutable else {
            throw ValidationError(
                "--linux requires --linux-executable <path to Linux ELF binary>. "
                    + "Build it first with: swift build -c release --product <YourApp>")
        }
        guard let arch = KSPackager.LinuxArchitecture(rawValue: linuxArch.lowercased()) else {
            throw ValidationError("--linux-arch must be 'x86_64' or 'aarch64' (got '\(linuxArch)').")
        }

        // 콤마 분리 형식 파싱.
        var formats: Set<KSPackager.LinuxFormat> = []
        for raw in linuxFormat.split(separator: ",") {
            let token = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if token == "all" {
                formats = Set(KSPackager.LinuxFormat.allCases)
                break
            }
            guard let f = KSPackager.LinuxFormat(rawValue: token) else {
                throw ValidationError(
                    "--linux-format token '\(token)' is invalid. Allowed: tarball, deb, appimage, all.")
            }
            formats.insert(f)
        }
        guard !formats.isEmpty else {
            throw ValidationError("--linux-format must contain at least one format.")
        }

        let exeURL = URL(fileURLWithPath: exeArg, relativeTo: cwd)
        let outputDir = output.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
            ?? cwd.appendingPathComponent("dist/linux-\(info.appName)-\(info.version)")
        let iconURL: URL? = linuxIcon.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
        let frontendDistURL: URL? = {
            if let raw = dist, !raw.isEmpty {
                return URL(fileURLWithPath: raw, relativeTo: cwd)
            }
            let fallback = cwd.appendingPathComponent(config.build.frontendDist)
            return fm.fileExists(atPath: fallback.path) ? fallback : nil
        }()

        let opts = KSPackager.LinuxOptions(
            executablePath: exeURL,
            configPath: try resolveConfigURL(cwd: cwd, fm: fm),
            frontendDist: frontendDistURL,
            output: outputDir,
            appName: info.appName,
            version: info.version,
            identifier: info.identifier,
            architecture: arch,
            formats: formats,
            iconPath: iconURL,
            maintainer: linuxMaintainer)

        print("📦  Packaging \(info.appName) Linux (\(formats.map { $0.rawValue }.sorted().joined(separator: "+"))) v\(info.version) → \(outputDir.path)")
        if dryrun {
            print("   (dry-run: skipping file emission)")
            return
        }
        let report = try KSPackager.runLinux(opts)
        print(report.description)
        print("ℹ  Next steps: see \(outputDir.path)/README.md for the exact tar/dpkg-deb/appimagetool commands.")
    }

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
        throw ValidationError("Could not find kalsae.json (use --config to override).")
    }

    private func loadConfig(configURL: URL) throws -> KSConfig {
        do {
            return try KSConfigLoader.load(from: configURL)
        } catch {
            throw ValidationError(
                "Failed to load \(configURL.lastPathComponent): \(error)")
        }
    }

    private func runCapabilityValidation(config: KSConfig, cwd: URL) throws {
        guard let mode = KSCapabilityValidator.Mode(rawValue: capabilityCheck) else {
            throw ValidationError(
                "--capability-check must be one of: strict | warn | off. Got '\(capabilityCheck)'.")
        }
        if mode == .off { return }

        let sources = KSBindingsGenerator.discoverSwiftFiles(
            under: cwd.appendingPathComponent("Sources"))
        let commands = KSBindingsGenerator.scanCommands(in: sources)
        let report = KSCapabilityValidator.validate(
            capabilities: config.capabilities, commands: commands)

        if report.findings.isEmpty {
            return
        }
        print("🛡  capability validator findings:")
        for f in report.findings {
            print("   \(f.description)")
        }
        if report.shouldFail(in: mode) {
            throw ValidationError(
                "Capability validation failed (mode: \(mode.rawValue)). "
                    + "Fix the errors above or rerun with --capability-check off.")
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

    /// `kalsae.json`에서 패키징에 필요한 메타데이터만 파싱한다.
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
