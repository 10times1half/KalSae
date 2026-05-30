// MARK: - Windows 패키징 (NSIS + MSI + MSIX)

#if os(Windows)
    import ArgumentParser
    import Foundation
    import KalsaeCLICore
    import KalsaeCore

    extension BuildCommand {
        /// Windows 실행 파일 패키징 및 인스톨러 생성 메인 진입점.
        ///
        /// ## 처리 단계
        /// 1. `.build/<configuration>/` 에서 `.exe` 위치 확인
        /// 2. WebView2 정책(`evergreen` / `fixed` / `auto`) 검증
        /// 3. KSPackager 실행: 디렉터리 구조 복사, frontend dist 포함, WebView2 runtime 배치
        /// 4. 필요한 경우 코드사이닝 (`--signtool-cmd`)
        /// 5. 필요한 경우 NSIS 인스톨러 생성 (`--nsis`) + 인스톨러 사이닝
        /// 6. 필요한 경우 WiX MSI 생성 (`--msi`) + MSI 사이닝
        ///
        /// ## Standalone 모드
        /// `--standalone` 이 설정되면 ResourceHacker로 PE 리소스를 실행 파일에 직접
        /// embed하고 외부 파일들을 제거하는 단일-바이너리 배포를 생성한다.
        /// `--standalone-allow-fallback` 이 없으면 ResourceHacker 부재 시 hard-error.
        func runPackageWindows(
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

            // 빌드된 .exe 경로 검증: `swift build` 가 완료된 직후여야 존재한다.
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

            // WebView2 vendor runtime: NuGet 패키지에서 다운로드한 WebView2Loader.dll 경로.
            // `Vendor/WebView2/runtimes/<arch>/` 에 위치하며, evergreen 정책일 때 필요.
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

            let rceditPath: URL? = {
                guard standalone else { return nil }
                do {
                    return try KSRceditProvisioner.ensure(
                        cwd: cwd, autoFetch: autoFetchRcedit)
                } catch {
                    print("⚠️   rcedit auto-fetch failed: \(error)")
                    return KSRceditProvisioner.locate()
                }
            }()

            // KSPackager 옵션 구성 — 이후 `KSPackager.run(opts)` 가 실제 파일 작업을 수행한다.
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
                resourceHackerPath: resourceHackerPath,
                rceditPath: rceditPath)

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

            if msi {
                try runPackageMSI(
                    config: config,
                    info: info,
                    cwd: cwd,
                    fm: fm,
                    outputURL: outputURL,
                    archEnum: archEnum)
            } else if msiSigntoolCmd != nil {
                print("⚠  --msi-signtool-cmd has no effect without --msi; skipping.")
            }
        }

        /// WiX v3 MSI 패키저.
        ///
        /// 호출 시점: `runPackageWindows`의 NSIS 블록 직후. 기존 산출물 폴더
        /// (`dist/<App>-<ver>-<arch>/`)를 staging 디렉터리로 사용하고
        /// `.wxs` + `.msi`를 그 부모 디렉터리에 만든다.
        ///
        /// ## WiX Toolset 의존성
        /// - `candle.exe`: `.wxs` → `.wixobj` 컴파일
        /// - `light.exe`: `.wixobj` → `.msi` 링크
        /// 두 실행 파일이 PATH에 없으면 `--auto-fetch-wix` (기본 ON)에 따라
        /// WiX v3.14를 자동 다운로드한다.
        ///
        /// ## 지역화
        /// `--msi-language` 또는 `kalsae.json windows.wix.language` 로 다국어 MSI 지원.
        /// 각 언어별 `.wxl` locale 경로가 있으면 light.exe에 반영된다.
        ///
        /// ## UpgradeCode
        /// 우선 순위: `--msi-upgrade-code` CLI > `kalsae.json windows.wix.upgradeCode`
        /// > `KSUUIDv5.wixUpgradeCode()` (DNS namespace 기반 결정론적 UUID).
        func runPackageMSI(
            config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager,
            outputURL: URL, archEnum: KSPackager.Architecture
        ) throws {
            let wixCfg = config.windowsBundle?.wix
            // UpgradeCode 결정.
            let upgrade: UUID = {
                if let cli = msiUpgradeCode,
                    !cli.isEmpty,
                    let u = UUID(uuidString: cli)
                {
                    return u
                }
                if let s = wixCfg?.upgradeCode,
                    !s.isEmpty,
                    let u = UUID(uuidString: s)
                {
                    return u
                }
                return KSUUIDv5.wixUpgradeCode(
                    productName: info.appName, arch: archEnum.rawValue)
            }()

            // 언어 결정 — CLI > kalsae.json > en-US.
            let langs: [String] = {
                if let cli = msiLanguage,
                    !cli.isEmpty
                {
                    return cli.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
                if let l = wixCfg?.language {
                    let tags = l.tags
                    if !tags.isEmpty { return tags }
                }
                return ["en-US"]
            }()
            // 각 언어별 .wxl locale 경로 매핑.
            var localePaths: [String: String] = [:]
            if let l = wixCfg?.language {
                for tag in langs {
                    if let p = l.localePath(for: tag) {
                        localePaths[tag] = URL(fileURLWithPath: p, relativeTo: cwd).path
                    }
                }
            }

            // Banner / Dialog 이미지.
            let bannerPath: URL? = {
                if let cli = msiBanner, !cli.isEmpty {
                    return URL(fileURLWithPath: cli, relativeTo: cwd)
                }
                if let s = wixCfg?.bannerPath, !s.isEmpty {
                    return URL(fileURLWithPath: s, relativeTo: cwd)
                }
                return nil
            }()
            let dialogPath: URL? = {
                if let cli = msiDialogImage, !cli.isEmpty {
                    return URL(fileURLWithPath: cli, relativeTo: cwd)
                }
                if let s = wixCfg?.dialogImagePath, !s.isEmpty {
                    return URL(fileURLWithPath: s, relativeTo: cwd)
                }
                return nil
            }()
            let iconURL: URL? = {
                if let icn = icon, !icn.isEmpty {
                    return URL(fileURLWithPath: icn, relativeTo: cwd)
                }
                return nil
            }()

            // WebView2 부트스트래퍼 파일명 (NSIS 블록과 동일 로직).
            let bootstrapName: String? =
                bootstrapper.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? KSPackager.detectBootstrapperFileName(in: outputURL)

            // WiX fragment paths: 별도의 .wxs 조각 파일들을 포함시킨다.
            let fragmentURLs: [URL] =
                (wixCfg?.fragmentPaths ?? []).map { URL(fileURLWithPath: $0, relativeTo: cwd) }

            let allowDowngrades = config.windowsBundle?.allowDowngrades ?? true
            let publisher = nsisPublisher ?? info.identifier
            let productVersion: String =
                wixCfg?.version.map(KSWiXTemplate.normalizeVersion)
                ?? KSWiXTemplate.normalizeVersion(info.version)

            let templateOpts = KSWiXTemplate.Options(
                appName: info.appName,
                version: productVersion,
                identifier: info.identifier,
                publisher: publisher,
                architecture: archEnum,
                sourceDir: outputURL,
                productCode: UUID(),
                upgradeCode: upgrade,
                iconPath: iconURL,
                allowDowngrades: allowDowngrades,
                bannerPath: bannerPath,
                dialogImagePath: dialogPath,
                webView2BootstrapperFileName: bootstrapName,
                webView2BootstrapperSilent: true,
                componentRefs: wixCfg?.componentRefs ?? [],
                componentGroupRefs: wixCfg?.componentGroupRefs ?? [],
                featureRefs: wixCfg?.featureRefs ?? [],
                featureGroupRefs: wixCfg?.featureGroupRefs ?? [],
                mergeRefs: wixCfg?.mergeRefs ?? [])

            let wixOpts = KSPackager.WiXOptions(
                template: templateOpts,
                languages: langs,
                localePaths: localePaths,
                fragmentPaths: fragmentURLs,
                autoFetchWiX: autoFetchWix,
                useLocalToolsDir: useLocalToolsDir,
                projectRoot: cwd)

            print("🛠️   Generating MSI installer (WiX v3)…")
            let report = try KSPackager.runWiX(wixOpts)
            print(report.description)

            // MSI 사이닝.
            if let template = msiSigntoolCmd, !template.isEmpty {
                if report.installerPaths.isEmpty {
                    print("⚠  --msi-signtool-cmd: light.exe did not produce an installer; skipping.")
                } else {
                    for path in report.installerPaths {
                        try KSSigntoolHook.run(
                            template: template,
                            file: URL(fileURLWithPath: path),
                            label: "signtool (msi)", dryrun: dryrun)
                    }
                }
            }
            _ = fm
        }

        /// Microsoft Store MSIX 패키저 (RFC-008 Phase 2).
        ///
        /// 호출 시점: `runPackageWindows` 가 끝난 직후. 기존 산출물 폴더
        /// (`dist/<App>-<ver>-<arch>/`) 를 **staging 디렉터리로 그대로 사용**한다.
        /// MSIX 매니페스트와 Assets/ 만 추가 작성하고 MakeAppx 를 호출한다.
        ///
        /// ## MSIX 파이프라인 단계
        /// 1. Assets/ 디렉터리에 5종 이미지 보장 (사용자 제공 or placeholder 1x1 PNG)
        /// 2. AppxManifest.xml 생성 (publisher, deep link, startup task 포함)
        /// 3. MakeAppx.exe 호출로 .msix 패키징
        /// 4. signtool.exe 호출로 서명 (`--msix-signtool-cmd`)
        ///
        /// ## Partner Center 제출 전 필수 작업
        /// - placeholder PNG → 실제 크기별 로고 이미지 교체
        /// - Publisher DN 이 Partner Center 등록과 일치해야 함
        /// - WACK(Windows App Certification Kit) 통과 필요
        func runPackageMSIX(
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
            // startup task: `autostart` 가 설정된 경우 MSIX 매니페스트에
            // StartupTask 선언을 추가해 OS 로그인 시 자동 실행을 지원한다.
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
        /// MSIXArchitecture rawValue 는 `x64` / `x86` / `arm64` 만 허용하므로,
        /// `x86_64`, `amd64` 등 흔한 별칭을 폴백 처리한다.
        func msixArchFallback(_ raw: String) -> KSPackager.MSIXArchitecture? {
            switch raw {
            case "x86_64", "x86-64", "amd64": return .x64
            case "i386", "i686": return .x86
            default: return nil
            }
        }

        /// `"CN=Acme Inc, O=..., C=KR"` → `"Acme Inc"`. 실패 시 nil.
        /// MSIX 매니페스트의 `<PublisherDisplayName>` 에 사용할 사람-친화적 이름을
        /// X.500 Distinguished Name 에서 추출한다. 실제 표시용이므로 정확한 DN 구문
        /// 분석보다는 간단한 CN 추출로 충분하다.
        func deriveCN(from dn: String) -> String? {
            for raw in dn.split(separator: ",") {
                let part = raw.trimmingCharacters(in: .whitespaces)
                if part.lowercased().hasPrefix("cn=") {
                    return String(part.dropFirst(3))
                }
            }
            return nil
        }

        /// 사용자 Assets 디렉터리가 있으면 복사, 없으면 placeholder PNG 5종 생성.
        ///
        /// MSIX에 필요한 5개 이미지:
        /// - `Square150x150Logo.png` (시작 메뉴, 작업 표시줄)
        /// - `Square44x44Logo.png` (앱 아이콘)
        /// - `Wide310x150Logo.png` (시작 메뉴 wide 타일)
        /// - `StoreLogo.png` (Microsoft Store 목록)
        /// - `SplashScreen.png` (스플래시 화면)
        ///
        /// placeholder는 1x1 투명 PNG로, WACK 통과에는 충분하지만
        /// Partner Center 제출 전에 반드시 실제 크기의 이미지로 교체해야 한다.
        func installMSIXAssets(
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
                            try _ksMSIXPlaceholderPNG.write(to: d)
                        }
                        print("⚠  Missing MSIX asset \(name); using placeholder.")
                    }
                }
            } else {
                for name in required {
                    let d = destination.appendingPathComponent(name)
                    if !fm.fileExists(atPath: d.path) {
                        try _ksMSIXPlaceholderPNG.write(to: d)
                    }
                }
                print(
                    "⚠  --msix-assets not provided; using placeholder PNGs for all 5 MSIX images. "
                        + "Replace before Partner Center submission.")
            }
        }
    }

    /// 1x1 투명 PNG (transparent), 67 bytes. WACK 는 사이즈를 엄밀히 보지 않지만
    /// Partner Center 제출 전에는 반드시 실제 사이즈로 교체해야 한다.
    ///
    /// 원본 `BuildCommand.placeholderPNG` 정적 저장 프로퍼티는 file-private 전역으로
    /// 옮겨졌다 — 확장(extension)은 저장 프로퍼티를 가질 수 없기 때문이다.
    private let _ksMSIXPlaceholderPNG: Data = Data([
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
