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

    // MARK: - 기본 빌드 옵션

    @Flag(name: .shortAndLong, help: "Build in debug configuration instead of release.")
    var debug: Bool = false

    @Option(name: .shortAndLong, help: "Executable target to build (optional).")
    var target: String? = nil

    @Option(
        name: [.customShort("j"), .long],
        help: "Maximum number of parallel swift build jobs (default: CPU count).")
    var jobs: Int? = nil

    // MARK: - 패키징 옵션

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
            "Standalone runtime install mode: download (fetch bootstrapper at runtime) | embedBootstrapper (bundle ~2 MB Evergreen bootstrapper) | offlineInstaller (experimental — currently equivalent to embedBootstrapper; standalone offline installer fetch is a planned RFC) | fixedVersion (experimental — requires manually populated `Vendor/WebView2/runtimes/win-<arch>/`; auto-fetch unimplemented) | skip (no runtime check)."
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

    // MARK: - 경로/출력 옵션

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
        name: .long,
        help:
            "Skip orphan removal during resource sync. Useful for one-off debugging when you have local files in Resources/ that are not in dist."
    )
    var noPrune: Bool = false

    // MARK: - Windows 전용 옵션

    @Flag(
        name: .long, inversion: .prefixedNo,
        help:
            "Windows: stage Swift runtime + VC redist DLLs (swift_Concurrency.dll, swiftCore.dll, vcruntime140.dll, …) next to the built executable so it runs on machines without a Swift toolchain. Default ON. On non-Windows hosts this is a no-op."
    )
    var stageRuntime: Bool = true

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

    @Flag(
        name: .long, inversion: .prefixedNo,
        help:
            "Automatically download rcedit when --standalone is on and it is missing (Windows only)."
    )
    var autoFetchRcedit: Bool = true

    // MARK: - 빌드 제어 옵션

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

    // MARK: - Windows 인스톨러 옵션 (NSIS)

    @Flag(
        name: .long,
        help: "Generate an NSIS installer (.nsi + .exe via makensis) after packaging. Windows-only.")
    var nsis: Bool = false

    @Option(
        name: .long,
        help: "Hint passed to the NSIS template Publisher field (default: app.identifier).")
    var nsisPublisher: String? = nil

    // MARK: - 코드사이닝 및 MSI 옵션

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
        name: .long,
        help:
            "Generate an MSI installer (.wxs + .msi via WiX Toolset v3) after packaging. Windows-only."
    )
    var msi: Bool = false

    @Option(
        name: .long,
        help:
            "Override the MSI UpgradeCode. Default: deterministic UUIDv5 of `<productName>.exe.app.<arch>` in DNS namespace (Tauri-compatible)."
    )
    var msiUpgradeCode: String? = nil

    @Option(
        name: .long,
        help:
            "Comma-separated MSI language tags (e.g. en-US,ko-KR). Default: en-US, or kalsae.json windows.wix.language."
    )
    var msiLanguage: String? = nil

    @Option(
        name: .long,
        help:
            "Path to MSI installer top banner BMP (493x58). Overrides kalsae.json windows.wix.bannerPath."
    )
    var msiBanner: String? = nil

    @Option(
        name: .long,
        help:
            "Path to MSI installer dialog background BMP (493x312). Overrides kalsae.json windows.wix.dialogImagePath."
    )
    var msiDialogImage: String? = nil

    @Option(
        name: .long,
        help:
            "Windows: codesign the MSI installer after light.exe. Same template syntax as --signtool-cmd (also accepts Tauri-style %1). Requires --msi."
    )
    var msiSigntoolCmd: String? = nil

    @Flag(
        name: .long, inversion: .prefixedNo,
        help:
            "Automatically download WiX Toolset v3.14 when --msi is on and candle.exe/light.exe are missing (Windows only). Default ON."
    )
    var autoFetchWix: Bool = true

    @Flag(
        name: .long,
        help:
            "Cache WiX binaries under <project>/.kalsae/tools/ instead of %LOCALAPPDATA%. Useful for CI/Docker."
    )
    var useLocalToolsDir: Bool = false

    // MARK: - 타이밍/성능 옵션

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

    // MARK: - 배포/스토어 옵션 (RFC-008)

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

    // MARK: - iOS App Store 옵션

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

    // MARK: - MSIX 옵션

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

    /// 명령줄 인자의 유효성을 `swift-argument-parser`의 기본 파싱 이후에 추가 검증한다.
    /// - `--jobs`가 양의 정수인지 확인
    /// - `--webview2-install-mode`가 허용된 값 중 하나인지 확인 (대시 제거 후 비교로 사용자 실수 완화)
    /// - `--store`가 유효한 distribution target 문자열인지 확인
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
                    if stageRuntime {
                        _ = try KSWindowsRuntimeStager.stageBuildOutputs(
                            cwd: cwd, configuration: configuration)
                    }
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
                if stageRuntime {
                    _ = try KSWindowsRuntimeStager.stageBuildOutputs(
                        cwd: cwd, configuration: configuration)
                }
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
    func resolveDistributionTarget(config: KSConfig) -> KSDistributionTarget {
        if let raw = store, let parsed = KSDistributionTarget.parse(raw) {
            return parsed
        }
        return config.distribution.target
    }

    func parseInstallMode(_ raw: String) -> KSPackager.WebView2InstallMode? {
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
}
