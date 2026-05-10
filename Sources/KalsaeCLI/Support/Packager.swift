/// SwiftPM 출력물, 프론트엔드 에셋, 설정 및 매니페스트로부터
/// 배포 가능한 Windows 번들을 빌드합니다.
/// WebView2 fixed runtime 모드의 경우, vendor 파일들은 다음 위치로부터 복사됩니다.
/// `Vendor/WebView2/runtimes/`.
public import Foundation

public enum KSPackager {
    public enum WebView2Policy: String, Sendable, CaseIterable {
        case evergreen
        case fixed
        case auto
    }

    public enum WebView2InstallMode: String, Sendable, CaseIterable {
        case download
        case embedBootstrapper
        case offlineInstaller
        case fixedVersion
        case skip
    }

    public enum Architecture: String, Sendable, CaseIterable {
        case x64 = "x64"
        case arm64 = "arm64"
        case x86 = "x86"

        public var vendorRuntimeFolder: String {
            switch self {
            case .x64: return "win-x64"
            case .arm64: return "win-arm64"
            case .x86: return "win-x86"
            }
        }

        /// Win32 SxS manifest `processorArchitecture` 값.
        ///
        /// 스펙(MSDN "Application Manifests")이 허용하는 값은
        /// `x86 | amd64 | arm64 | ia64 | msil | *` 뿐이다. 우리는 CLI 입력과
        /// 출력 디렉터리 표면에서 `x64` 표기를 쓰므로 manifest 작성 직전
        /// 한 번만 `amd64` 로 변환한다. 이 변환을 빠뜨리면 OS SxS 로더가
        /// `processorArchitecture="x64"` 를 거부해 EXE 시작 자체가 실패한다
        /// ("side-by-side 구성이 잘못되어...").
        public var manifestProcessorArchitecture: String {
            switch self {
            case .x64: return "amd64"
            case .arm64: return "arm64"
            case .x86: return "x86"
            }
        }
    }

    public struct Options: Sendable {
        public var projectRoot: URL
        public var executablePath: URL  // Built .exe to copy into bundle
        public var configPath: URL  // Kalsae.json
        public var frontendDist: URL?  // Dist directory (nil for dev-server only)
        public var output: URL  // dist/<name>-<version>-<arch>/
        public var appName: String
        public var version: String
        public var identifier: String
        public var architecture: Architecture
        public var policy: WebView2Policy
        public var standalone: Bool
        /// `standalone` 이면서 PE 편집기(ResourceHacker / rcedit)가
        /// PATH 에 없을 때, true 면 경고만 남기고 외부 파일 구성으로
        /// 폴백. false 면 패키지에서 hard-error 를 던져 사일랰트 실패를
        /// 차단한다. CLI 기본값은 false (`--standalone-allow-fallback` 로
        /// 옵트인). 라이브러리 기본값은 true (기존 테스트 호환).
        public var standaloneAllowFallback: Bool
        public var webView2InstallMode: WebView2InstallMode?
        public var iconPath: URL?  // .ico copied as-is when present
        public var vendorRuntimeRoot: URL?  // Vendor/WebView2/runtimes/<arch>/
        public var bootstrapperPath: URL?  // MicrosoftEdgeWebview2Setup.exe (optional)
        public var zip: Bool  // Create <output>.zip when true
        /// 패키징 시 소스맵(.map) 파일을 자동 제거한다.
        public var stripSourceMaps: Bool
        /// 패키징 시 추가로 제거할 파일 확장자 목록.
        public var stripExtensions: [String]
        /// `--standalone` 일 때 PE embed 에 사용할 ResourceHacker.exe 경로
        /// (KSResourceHackerProvisioner 결과). nil 이면 PATH 만 사용.
        public var resourceHackerPath: URL?

        public init(
            projectRoot: URL,
            executablePath: URL,
            configPath: URL,
            frontendDist: URL?,
            output: URL,
            appName: String,
            version: String,
            identifier: String,
            architecture: Architecture,
            policy: WebView2Policy,
            standalone: Bool = false,
            standaloneAllowFallback: Bool = true,
            webView2InstallMode: WebView2InstallMode? = nil,
            iconPath: URL? = nil,
            vendorRuntimeRoot: URL? = nil,
            bootstrapperPath: URL? = nil,
            zip: Bool = false,
            stripSourceMaps: Bool = true,
            stripExtensions: [String] = [],
            resourceHackerPath: URL? = nil
        ) {
            self.projectRoot = projectRoot
            self.executablePath = executablePath
            self.configPath = configPath
            self.frontendDist = frontendDist
            self.output = output
            self.appName = appName
            self.version = version
            self.identifier = identifier
            self.architecture = architecture
            self.policy = policy
            self.standalone = standalone
            self.standaloneAllowFallback = standaloneAllowFallback
            self.webView2InstallMode = webView2InstallMode
            self.iconPath = iconPath
            self.vendorRuntimeRoot = vendorRuntimeRoot
            self.bootstrapperPath = bootstrapperPath
            self.zip = zip
            self.stripSourceMaps = stripSourceMaps
            self.stripExtensions = stripExtensions
            self.resourceHackerPath = resourceHackerPath
        }
    }

    public struct Report: Sendable, CustomStringConvertible {
        public let outputPath: String
        public let zipPath: String?
        public let policy: String
        public let warnings: [String]
        /// standalone 빌드일 때 PE embed 결과. 일반 빌드에서는 nil.
        public let standalone: StandaloneEmbedReport?

        public struct StandaloneEmbedReport: Sendable {
            public let loaderEmbedded: Bool
            public let manifestEmbedded: Bool
            public let assetsEmbedded: Bool
            public let configEmbedded: Bool
            public let runtimeEmbedded: Bool
            public let iconEmbedded: Bool
            public let versionEmbedded: Bool
        }

        public var description: String {
            var s = "Packaged \(policy) at \(outputPath)"
            if let z = zipPath { s += "\nArchive: \(z)" }
            if let st = standalone {
                func mark(_ ok: Bool) -> String { ok ? "✔" : "✘" }
                s += "\nStandalone embed:"
                s += "\n  \(mark(st.loaderEmbedded)) WebView2Loader.dll (RCDATA)"
                s += "\n  \(mark(st.manifestEmbedded)) RT_MANIFEST"
                s += "\n  \(mark(st.assetsEmbedded)) frontend assets (RCDATA)"
                s += "\n  \(mark(st.configEmbedded)) Kalsae.json (RCDATA)"
                s += "\n  \(mark(st.runtimeEmbedded)) kalsae.runtime.json (RCDATA)"
                s += "\n  \(mark(st.iconEmbedded)) icon"
                s += "\n  \(mark(st.versionEmbedded)) version metadata"
            }
            for w in warnings { s += "\n  ! \(w)" }
            return s
        }
    }

    /// Standalone PE 편집기 부재 시 패키지에서 던지는 에러.
    /// `--standalone-allow-fallback` 플래그 없이 실제 standalone 빌드가
    /// 일반 빌드와 구별없는 상태로 배포되는 것을 차단한다.
    public struct StandaloneToolsMissingError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    /// Runs packaging: file copy, manifest/runtime materialization,
    /// and optional zip archive creation.
    public static func run(_ opts: Options) throws -> Report {
        let fm = FileManager.default
        var warnings: [String] = []

        // Output 디렉터리 청소 정책 (RFC-002 §3.1(a)):
        // 직전 빌드의 fingerprint 와 이번 빌드의 fingerprint 를 비교해, 정책/아키텍처/
        // exeName/icon/version/identifier 중 하나라도 바뀌면 stale 산출물(예:
        // 정책 전환 시 남는 webview2-runtime/, 아키텍처 변경 시 잘못된 DLL 등)을
        // 제거하기 위해 output 전체를 삭제한다. 동일하면 증분 빌드.
        let fingerprintURL = opts.output.appendingPathComponent(".kalsae-pkg-fingerprint.json")
        let currentFP = Fingerprint.from(opts)
        let previousFP = Fingerprint.load(at: fingerprintURL)
        if fm.fileExists(atPath: opts.output.path), previousFP != currentFP {
            // Windows CI: Defender / Search Indexer 가 직전 빌드 산출물(특히
            // `webview2-runtime/` 의 EXE/DLL) 핸들을 잠시 잡고 있을 때
            // ERROR_SHARING_VIOLATION (Win32 32) 으로 실패한다. 짧은 retry 로
            // 폴백 (AGENTS.md §6).
            try retryingTransient {
                try fm.removeItem(at: opts.output)
            }
        }
        try fm.createDirectory(at: opts.output, withIntermediateDirectories: true)

        // 1) Executable
        let exeName = "\(opts.appName).exe"
        let dstExe = opts.output.appendingPathComponent(exeName)
        try safeCopy(from: opts.executablePath, to: dstExe, fm: fm)

        // 1.5) WebView2Loader.dll — `CKalsaeWV2` 가 런타임에 `LoadLibraryW`
        // 로 동적 로드한다. EXE 옆에 없으면 `HRESULT 0x8007007E`
        // (ERROR_MOD_NOT_FOUND) 로 환경 생성에 실패한다. 시스템에 Edge
        // WebView2 가 깔린 머신에서는 search path 폴백으로 우연히
        // 동작할 수 있으나, 깨끗한 머신/오프라인 배포에서는 즉시 실패하므로
        // 패키지에 항상 포함시킨다.
        copyLoaderDLL(opts: opts, warnings: &warnings)

        // 2) Side-by-side manifest (DPI awareness, asInvoker)
        let manifestURL = opts.output.appendingPathComponent("\(exeName).manifest")
        try renderManifest(opts: opts).write(
            to: manifestURL,
            atomically: false,
            encoding: .utf8)

        // 3. Kalsae.json ?ㅼ젙.
        let dstConfig = opts.output.appendingPathComponent("Kalsae.json")
        try safeCopy(from: opts.configPath, to: dstConfig, fm: fm)

        // 3.1 패키저는 frontend dist 를 항상 `Resources/` 로 복사하므로 소스
        // `Kalsae.json` 의 `build.frontendDist`(예: "dist")가 그대로 남으면
        // 런타임에 `<exeDir>/<frontendDist>` 가 존재하지 않아 KSApp.boot 가 dev 서버
        // fallback 으로 빠지면서 흰 화면 + chrome-error 가 된다. release 빌드에서는
        // `security.devtools` 도 안전하게 끈다(KSSecurityConfig.devtools 문서화 동작).
        try KSPackager.rewritePackagedConfig(
            at: dstConfig,
            frontendDist: "Resources",
            disableDevtools: true)

        // 4) Frontend assets
        if let dist = opts.frontendDist, fm.fileExists(atPath: dist.path) {
            let dstResources = opts.output.appendingPathComponent("Resources")

            // 자기-복사 방지: 출력 디렉터리(`opts.output`)가 `dist/` 안에 위치하면
            // (예: 새 템플릿의 `frontendDist: "../../../dist"` + 출력 기본 위치
            // `<root>/dist/<APP>-<VER>-<ARCH>-standalone/`) 단순 `copyItem(dist→…)`
            // 은 출력 패키지를 자기 자신 안으로 무한 재귀 복사한다. 이 경우
            // ResourceSyncManager 도 같은 입력을 처리하므로 우회로 진입을 막는다.
            //
            // Windows 의 `URL.standardizedFileURL.path` 는 cwd 입력 케이스 / 구분자
            // / trailing slash 유무에 따라 raw 형태가 흔들려 prefix 비교가 빗나간다
            // (testks2 소문자 cwd 회귀). `KSResourceSyncManager.overlaps()` 와 동일한
            // 정규화로 결정적 비교.
            let distStd = canonicalPathForContainsCheck(dist)
            let outStd = canonicalPathForContainsCheck(opts.output)
            let outputInsideDist =
                outStd == distStd || outStd.hasPrefix(distStd + "/")
            // 증분 sync (RFC-002 §3.1(c)):
            // dst 가 이미 있으면 KSResourceSyncManager.sync 로 size+mtime 비교 증분
            // 복사. 최소 빌드(dst 미존재)는 기존 전체 복사로 폴백.
            // `preserved: []` — 패키저 output 의 `Resources/` 에는 dist 의 frontend
            // 자산만 들어가고 (`Kalsae.json` 은 step 3 에서 output 루트에 별도 배치),
            // sentinel 보존 대상이 없다.
            if outputInsideDist {
                // dist 안에 output 이 있을 때는 entry-by-entry 복사로 output
                // 서브트리만 건너뛴다.
                try copyDistExcludingOutput(
                    dist: dist,
                    dstResources: dstResources,
                    output: opts.output,
                    fm: fm)
            } else if fm.fileExists(atPath: dstResources.path) {
                _ = try KSResourceSyncManager.sync(
                    distURL: dist,
                    resourcesURL: dstResources,
                    preserved: [],
                    fm: fm)
            } else {
                try fm.copyItem(at: dist, to: dstResources)
            }

            // Strip 불필요한 파일 (소스맵 등)
            let stripResult = KSBundleAnalyzer.strip(
                distURL: dstResources,
                stripSourceMaps: opts.stripSourceMaps,
                stripExtensions: opts.stripExtensions)
            if stripResult.removed > 0 {
                let msg =
                    "  🗑  Stripped \(stripResult.removed) file(s) (\(KSBundleReport.formatBytes(stripResult.savedBytes)))"
                print(msg)
            }
            if stripResult.failed > 0 {
                warnings.append(
                    "Failed to strip \(stripResult.failed) file(s) from frontend bundle (locked or read-only).")
            }
        } else {
            warnings.append("Frontend dist directory not found; skipping Resources/.")
        }

        // 5) Icon (optional)
        if let icon = opts.iconPath, fm.fileExists(atPath: icon.path) {
            let dst = opts.output.appendingPathComponent(icon.lastPathComponent)
            try safeCopy(from: icon, to: dst, fm: fm)
        }

        // 6) WebView2 runtime policy materialization
        var runtime: [String: Any] = [
            "policy": opts.policy.rawValue,
            "identifier": opts.identifier,
            "userDataFolder": "%LOCALAPPDATA%\\\(opts.identifier)\\WebView2",
        ]

        let installMode = effectiveInstallMode(opts)
        runtime["installMode"] = installMode.rawValue

        switch installMode {
        case .download:
            runtime["installBehavior"] = "download-bootstrapper-at-runtime"
        case .skip:
            runtime["installBehavior"] = "skip-runtime-install-check"
            warnings.append(
                "WebView2 install mode is 'skip': app startup may fail on machines without a system WebView2 runtime."
            )
        case .embedBootstrapper, .offlineInstaller:
            runtime["installBehavior"] =
                installMode == .offlineInstaller
                ? "embedded-offline-installer"
                : "embedded-bootstrapper"
            try copyBootstrapper(
                opts: opts,
                warnings: &warnings)
        case .fixedVersion:
            runtime["installBehavior"] = "fixed-runtime-folder"
            try copyFixedRuntime(
                opts: opts, runtime: &runtime,
                warnings: &warnings)
        }

        let runtimeURL = opts.output.appendingPathComponent("kalsae.runtime.json")

        // 7) Standalone 후처리 파이프라인. PE 편집기(ResourceHacker / rcedit) 로
        //    WebView2Loader.dll / RT_MANIFEST / icon / version / asset zip 을 EXE 내부에
        //    embed 하고, 성공한 대상의 외부 파일은 제거한다. PE 편집기가 없으면
        //    `standaloneAllowFallback` 여부에 따라 (a) 경고 + 호환성 폴백 혹은
        //    (b) hard-error 로 끝난다.
        var standaloneEmbed: Report.StandaloneEmbedReport? = nil
        if opts.standalone {
            var embeddedAssetsZipURL: URL?
            if let frontendDist = opts.frontendDist, fm.fileExists(atPath: frontendDist.path) {
                do {
                    let report = try KSAssetZipBuilder.build(from: frontendDist)
                    let tempZip = fm.temporaryDirectory
                        .appendingPathComponent("kalsae-standalone-assets-\(UUID().uuidString)")
                        .appendingPathExtension("zip")
                    try report.zipData.write(to: tempZip, options: [.atomic])
                    embeddedAssetsZipURL = tempZip
                    runtime["embeddedAssetsResourceName"] = "KSAS_ASSETS_ZIP"
                    runtime["embeddedAssetsFileCount"] = report.fileCount
                    // standalone 모드는 RCDATA asset zip 사용을 의도한다. 후처리가
                    // 실패하면 이후 분기에서 toolsMissing hard-error 로 빠지므로
                    // 여기서 미리 기록해도 안전하다 (runtime.json 도 같은 후처리
                    // 단계에서 임베드되므로 두 값이 함께 산출물에 들어간다).
                    runtime["embeddedAssetsEnabled"] = true
                } catch {
                    warnings.append("Standalone asset zip build failed: \(error)")
                }
            }

            defer {
                if let embeddedAssetsZipURL {
                    try? fm.removeItem(at: embeddedAssetsZipURL)
                }
            }

            // kalsae.runtime.json 도 RCDATA 로 임베드한다 (fixed runtime 정책 제외).
            // fixed 는 외부 webview2-runtime/ 폴더 절대/상대 경로를 참조하므로
            // 외부 파일을 유지하는 편이 안전하다.
            let shouldEmbedRuntime = installMode != .fixedVersion
            var embeddedRuntimeJSONURL: URL?
            if shouldEmbedRuntime {
                do {
                    let runtimeJSONData = try JSONSerialization.data(
                        withJSONObject: runtime,
                        options: [.prettyPrinted, .sortedKeys])
                    let tempRuntime = fm.temporaryDirectory
                        .appendingPathComponent("kalsae-standalone-runtime-\(UUID().uuidString)")
                        .appendingPathExtension("json")
                    try runtimeJSONData.write(to: tempRuntime, options: [.atomic])
                    embeddedRuntimeJSONURL = tempRuntime
                } catch {
                    warnings.append("Standalone runtime.json embed prep failed: \(error)")
                }
            }

            defer {
                if let embeddedRuntimeJSONURL {
                    try? fm.removeItem(at: embeddedRuntimeJSONURL)
                }
            }

            let standaloneReport = KSStandalonePostProcessor.run(
                .init(
                    executable: dstExe,
                    appName: opts.appName,
                    version: opts.version,
                    identifier: opts.identifier,
                    loaderDLL: opts.output.appendingPathComponent("WebView2Loader.dll"),
                    manifestPath: manifestURL,
                    iconPath: opts.iconPath,
                    assetsZipPath: embeddedAssetsZipURL,
                    configPath: dstConfig,
                    runtimePath: embeddedRuntimeJSONURL,
                    resourceHackerOverride: opts.resourceHackerPath))
            warnings.append(contentsOf: standaloneReport.warnings)

            // 임베드 메커니즘이 아예 동작하지 않고 fallback 도 허용되지 않으면 즉시 실패.
            // (in-process Win32 패치가 기본 경로이므로 보통 도달하지 않는다 —
            //  PE 가 손상됐거나 권한이 없을 때만 발생.)
            if standaloneReport.toolsMissing, !opts.standaloneAllowFallback {
                throw StandaloneToolsMissingError(
                    message:
                        "--standalone build could not embed any PE resource. The in-process Win32 "
                        + "patcher failed and no fallback PE editor (ResourceHacker / rcedit) is on PATH, "
                        + "so the package would be byte-identical to a non-standalone build. "
                        + "Re-run with `--standalone-allow-fallback` to ship the compatibility layout, "
                        + "or check the warnings above for the underlying GetLastError code.")
            }

            standaloneEmbed = Report.StandaloneEmbedReport(
                loaderEmbedded: standaloneReport.loaderEmbedded,
                manifestEmbedded: standaloneReport.manifestEmbedded,
                assetsEmbedded: standaloneReport.assetsEmbedded,
                configEmbedded: standaloneReport.configEmbedded,
                runtimeEmbedded: standaloneReport.runtimeEmbedded,
                iconEmbedded: standaloneReport.iconEmbedded,
                versionEmbedded: standaloneReport.versionEmbedded)

            if standaloneReport.assetsEmbedded {
                let resourcesPath = opts.output.appendingPathComponent("Resources")
                if fm.fileExists(atPath: resourcesPath.path) {
                    do {
                        try fm.removeItem(at: resourcesPath)
                    } catch {
                        warnings.append(
                            "Standalone post-process: embedded assets succeeded but failed to remove external Resources/: \(error)"
                        )
                    }
                }
            } else {
                // asset zip 임베드가 실패했다면 `embeddedAssetsEnabled` 플래그도 거짓.
                runtime["embeddedAssetsEnabled"] = false
            }

            if standaloneReport.loaderEmbedded {
                let loaderPath = opts.output.appendingPathComponent("WebView2Loader.dll")
                if fm.fileExists(atPath: loaderPath.path) {
                    do {
                        try fm.removeItem(at: loaderPath)
                    } catch {
                        warnings.append(
                            "Standalone post-process: embedded loader succeeded but failed to remove external WebView2Loader.dll: \(error)"
                        )
                    }
                }
            }

            if standaloneReport.manifestEmbedded,
                fm.fileExists(atPath: manifestURL.path)
            {
                do {
                    try fm.removeItem(at: manifestURL)
                } catch {
                    warnings.append(
                        "Standalone post-process: embedded manifest succeeded but failed to remove external .manifest: \(error)"
                    )
                }
            }

            // 외부 `Kalsae.json` 제거 — RCDATA 임베드가 성공했고 현재 저장소
            // 런타임은 `KSEmbeddedConfigLoader` (RCDATA 폴백) 를 가지고 있으므로
            // 디스크 사이드카 없이도 부팅이 가능하다. 사이드카가 남아 있으면
            // SwiftPM `<exe>_*.resources/` 의 잔존 `kalsae.json` 과 함께
            // `Bundle.module` 경로가 잘못된 `resourceRoot` 를 반환해 흰 화면이
            // 재발할 수 있다.
            if standaloneReport.configEmbedded,
                fm.fileExists(atPath: dstConfig.path)
            {
                do {
                    try fm.removeItem(at: dstConfig)
                } catch {
                    warnings.append(
                        "Standalone post-process: embedded config succeeded but failed to remove external Kalsae.json: \(error)"
                    )
                }
            }

            // SwiftPM `<Package>_<Target>.resources/` 잔존 디렉터리 제거.
            // `swift build` 산출물 디렉터리에서 그대로 복사된 EXE 옆에 이 폴더가
            // 함께 남아 있으면, 런타임의 `Bundle.module.url(forResource:)` 가
            // 거기서 `kalsae.json` 을 발견해 잘못된 resourceRoot 를 만든다.
            // standalone 모드는 RCDATA 임베드를 신뢰하므로 무조건 정리한다.
            if let entries = try? fm.contentsOfDirectory(atPath: opts.output.path) {
                for entry in entries where entry.hasSuffix(".resources") {
                    let path = opts.output.appendingPathComponent(entry)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: path.path, isDirectory: &isDir),
                        isDir.boolValue
                    {
                        try? fm.removeItem(at: path)
                    }
                }
            }
        }

        let runtimeData = try JSONSerialization.data(
            withJSONObject: runtime,
            options: [.prettyPrinted, .sortedKeys])
        // standalone 모드에서 runtime.json 임베드가 성공했으면 외부 디스크 사본을
        // 만들지 않는다 (KSWebView2Runtime.loadPolicy 가 RCDATA 폴백을 갖고 있다).
        // fixed runtime 정책 또는 임베드 실패 시에는 기존처럼 디스크에 쓴다.
        if standaloneEmbed?.runtimeEmbedded != true {
            try runtimeData.write(to: runtimeURL)
        } else if fm.fileExists(atPath: runtimeURL.path) {
            // 이전 빌드 산출물이 남아 있을 수 있다.
            try? fm.removeItem(at: runtimeURL)
        }

        // 8) Optional zip archive
        // Fingerprint 는 zip 생성 이후에 기록한다 (RFC-002 §3.1(d)). 이렇게
        // 하면 zip 호출 시점에 파일이 디스크에 존재하지 않아
        // KSZipArchiver 의 exclude API 로직 없이도 구조적으로 산출물에
        // 포함되지 않음을 보장한다.
        var zipPath: String? = nil
        if opts.zip {
            let archive = opts.output.deletingLastPathComponent()
                .appendingPathComponent("\(opts.appName)-\(opts.version)-\(opts.architecture.rawValue).zip")
            if fm.fileExists(atPath: archive.path) {
                try fm.removeItem(at: archive)
            }
            do {
                try createZip(from: opts.output, to: archive)
                zipPath = archive.path
            } catch {
                warnings.append("Failed to create zip: \(error)")
            }
        }

        // 9) Fingerprint 기록 — 다음 빌드의 incremental 여부 판단에만 사용.
        // zip 생성 이후에 하는 이유는 위 (7) 의 설명 참조. 기록 실패가
        // 치명적이지는 않으므로 warning 으로만 남긴다 (다음 빌드에서
        // fingerprint 부재로 취급 → 자동 전체 재생성).
        do {
            try currentFP.write(to: fingerprintURL)
        } catch {
            warnings.append("Failed to write packaging fingerprint: \(error)")
        }

        return Report(
            outputPath: opts.output.path,
            zipPath: zipPath,
            policy: opts.policy.rawValue,
            warnings: warnings,
            standalone: standaloneEmbed)
    }

    // MARK: - Packaged config rewrite

    /// 패키저가 만든 `Kalsae.json` 을 패키지 산출물 레이아웃에 맞게 다시 쓴다.
    ///
    /// 패키저는 frontend dist 폴더를 자체 명명 규칙(`Resources/` for Windows/Linux,
    /// inline for macOS)으로 복사하기 때문에, 원본 `Kalsae.json` 의
    /// `build.frontendDist` 가 다른 이름(예: "dist")으로 남아 있으면 런타임의
    /// `<configDir>/<frontendDist>` 해석이 빗나가 dev 서버 fallback → 흰 화면이 된다.
    ///
    /// `clearDevServerURL` 이 true 면(기본값) `build.devServerURL` 을 `"about:blank"`
    /// 으로 강제 덮어쓴다. 산출물에 `http://localhost:5173` 같은 잔존 dev URL 이
    /// 남아 있으면 `KSApp.boot` 의 release 가드가 들어가도 사용자가 직접 config
    /// 를 수정해 dev 분기로 빠질 수 있어, 패키저 단계에서 함께 무력화하면
    /// "패키징 산출물이 우연히 dev 서버를 시도 → 흰 화면" 회귀를 차단한다.
    /// 키를 삭제하지 않고 `"about:blank"` 로 두는 이유는 `KSConfig.build.devServerURL`
    /// 이 non-optional `String` 이라 누락 시 디코드가 실패하기 때문이다.
    ///
    /// JSONSerialization 으로 파싱→수정→재직렬화하여 Codable 모델이 모르는 미래
    /// 필드도 보존한다.
    static func rewritePackagedConfig(
        at url: URL,
        frontendDist: String,
        disableDevtools: Bool,
        clearDevServerURL: Bool = true
    ) throws {
        let data = try Data(contentsOf: url)
        guard
            var root = try JSONSerialization.jsonObject(with: data, options: [])
                as? [String: Any]
        else { return }

        var build = (root["build"] as? [String: Any]) ?? [:]
        build["frontendDist"] = frontendDist
        if clearDevServerURL {
            // release 산출물에서 `KSApp.boot` 의 dev-server 분기를 원천 차단.
            // `isRemoteURL("about:blank")` 가 false 이므로 자동 호환된다.
            build["devServerURL"] = "about:blank"
        }
        root["build"] = build

        if disableDevtools {
            var security = (root["security"] as? [String: Any]) ?? [:]
            security["devtools"] = false
            root["security"] = security
        }

        let out = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys])
        // Windows: Defender / Search Indexer가 방금 copy 된 Kalsae.json 핸들을
        // 잠시 들고 있을 수 있어 atomic write가 ERROR_SHARING_VIOLATION (Win32 32)
        // 으로 실패할 수 있다. 짧은 retry 로 대응한다 (AGENTS.md §6).
        try retryingTransient {
            try out.write(to: url, options: [.atomic])
        }
    }

    // MARK: - Manifest

    private static func renderManifest(opts: Options) -> String {
        // Win10/11 manifest: PerMonitorV2 DPI awareness, Common Controls v6,
        // and `asInvoker` execution level so normal users can run without UAC prompts.
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
            <assemblyIdentity
            type="win32"
            name="\(opts.identifier)"
            version="\(normalizedVersion(opts.version))"
            processorArchitecture="\(opts.architecture.manifestProcessorArchitecture)"/>
            <description>\(opts.appName)</description>
            <dependency>
            <dependentAssembly>
            <assemblyIdentity
            type="win32"
            name="Microsoft.Windows.Common-Controls"
            version="6.0.0.0"
            processorArchitecture="*"
            publicKeyToken="6595b64144ccf1df"
            language="*"/>
            </dependentAssembly>
            </dependency>
            <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
            <security>
            <requestedPrivileges>
            <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
            </requestedPrivileges>
            </security>
            </trustInfo>
            <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
            <application>
            <!-- Win10/11 -->
            <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
            </application>
            </compatibility>
            <application xmlns="urn:schemas-microsoft-com:asm.v3">
            <windowsSettings>
            <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
            <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
            </windowsSettings>
            </application>
            </assembly>
            """
    }

    /// Normalizes semver-like text into a 4-part `a.b.c.d` string for
    /// Win32 `assemblyIdentity` / VERSIONINFO.
    private static func normalizedVersion(_ raw: String) -> String {
        // Keep only the numeric head before prerelease/build metadata.
        let head =
            raw.split(
                separator: "-", maxSplits: 1,
                omittingEmptySubsequences: false
            ).first ?? "0"
        var parts = head.split(separator: ".").compactMap { Int($0) }
        while parts.count < 4 { parts.append(0) }
        return parts.prefix(4).map(String.init).joined(separator: ".")
    }

    // MARK: - WebView2 Runtime Helpers

    private static func effectiveInstallMode(_ opts: Options) -> WebView2InstallMode {
        if let mode = opts.webView2InstallMode {
            return mode
        }
        switch opts.policy {
        case .evergreen: return .download
        case .fixed: return .fixedVersion
        case .auto: return .embedBootstrapper
        }
    }

    /// `WebView2Loader.dll` 을 패키지 출력 루트에 복사한다.
    ///
    /// 후보 소스 위치(우선순위 순):
    ///   1. `opts.projectRoot/Vendor/WebView2/runtimes/<arch>/native/WebView2Loader.dll`
    ///      (Kalsae 본 저장소를 직접 빌드하는 경우)
    ///   2. `opts.projectRoot/.build/checkouts/*/Sources/CKalsaeWV2/Vendor/WebView2/runtimes/<arch>/native/WebView2Loader.dll`
    ///      (Kalsae 를 SwiftPM 의존성으로 사용하는 컨슈머 프로젝트)
    ///
    /// 어떤 후보도 찾지 못하면 hard error 가 아니라 warning 만 남긴다 — 시스템에
    /// Edge WebView2 가 설치된 머신에서는 search path 폴백으로 동작할 수 있고,
    /// 깨끗한 머신에 배포하기 직전에 사용자가 인지하면 충분하다.
    private static func copyLoaderDLL(
        opts: Options,
        warnings: inout [String]
    ) {
        let fm = FileManager.default
        let arch = opts.architecture.vendorRuntimeFolder

        var candidates: [URL] = []
        candidates.append(
            opts.projectRoot
                .appendingPathComponent("Vendor")
                .appendingPathComponent("WebView2")
                .appendingPathComponent("runtimes")
                .appendingPathComponent(arch)
                .appendingPathComponent("native")
                .appendingPathComponent("WebView2Loader.dll"))

        let checkouts =
            opts.projectRoot
            .appendingPathComponent(".build")
            .appendingPathComponent("checkouts")
        if let children = try? fm.contentsOfDirectory(
            at: checkouts,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        {
            for child in children {
                let dll =
                    child
                    .appendingPathComponent("Sources")
                    .appendingPathComponent("CKalsaeWV2")
                    .appendingPathComponent("Vendor")
                    .appendingPathComponent("WebView2")
                    .appendingPathComponent("runtimes")
                    .appendingPathComponent(arch)
                    .appendingPathComponent("native")
                    .appendingPathComponent("WebView2Loader.dll")
                candidates.append(dll)
            }
        }

        guard let src = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
            warnings.append(
                "WebView2Loader.dll not found in Vendor/WebView2/runtimes/\(arch)/native — "
                    + "the packaged app will fail to start on machines without a system-installed WebView2 runtime.")
            return
        }

        let dst = opts.output.appendingPathComponent("WebView2Loader.dll")
        do {
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
        } catch {
            warnings.append("Failed to stage WebView2Loader.dll: \(error)")
        }
    }

    private static func copyBootstrapper(
        opts: Options,
        warnings: inout [String]
    ) throws {
        guard let src = opts.bootstrapperPath else {
            warnings.append(
                "No WebView2 Evergreen bootstrapper supplied; the app will rely on a system-installed runtime.")
            return
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else {
            warnings.append("Bootstrapper not found at \(src.path); skipping.")
            return
        }
        let dst = opts.output.appendingPathComponent("MicrosoftEdgeWebview2Setup.exe")
        try safeCopy(from: src, to: dst)
    }

    /// 패키지 디렉터리에 WebView2 evergreen 부트스트랩이 들어 있으면 그 파일명을
    /// 반환한다 (NSIS 인스톨러가 silent 부트스트랩을 호출할지 결정하는 데 쓴다).
    public static func detectBootstrapperFileName(in dir: URL) -> String? {
        let fm = FileManager.default
        let candidate = dir.appendingPathComponent("MicrosoftEdgeWebview2Setup.exe")
        return fm.fileExists(atPath: candidate.path) ? candidate.lastPathComponent : nil
    }

    private static func copyFixedRuntime(
        opts: Options,
        runtime: inout [String: Any],
        warnings: inout [String]
    ) throws {
        guard let src = opts.vendorRuntimeRoot else {
            warnings.append("No fixed WebView2 runtime root supplied; skipping.")
            return
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else {
            warnings.append("Fixed WebView2 runtime not found at \(src.path); skipping.")
            return
        }
        let dst = opts.output.appendingPathComponent("webview2-runtime")
        try copyTree(from: src, to: dst)
        runtime["browserExecutableFolder"] = "webview2-runtime"
    }

    // MARK: - File System Helpers

    /// 증분 빌드 안전 덤프. dst 가 이미 존재하면 `removeItem` 후 복사하여
    /// `NSFileWriteFileExistsError` 를 회피한다.
    ///
    /// Windows 의 Defender / Search Indexer 가 방금 만든 exe/DLL 핸들을 잠시
    /// 들고 있을 때 `removeItem` 또는 `copyItem` 이 `ERROR_SHARING_VIOLATION`
    /// (Win32 32) 로 실패할 수 있다. 짧은 retry 로 대응한다 (RFC-002 follow-up).
    internal static func safeCopy(from src: URL, to dst: URL, fm: FileManager = .default) throws {
        try retryingTransient {
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: src, to: dst)
        }
    }

    /// 두 파일 URL 의 "포함 관계 (B ⊂ A)" 검사용 정규화된 경로 문자열.
    ///
    /// `URL.standardizedFileURL.path` 는 Windows 에서 cwd 입력 케이스 / 분리자
    /// (`\\` vs `/`) / trailing slash 유무에 따라 raw 형태가 흔들려 단순
    /// `hasPrefix` 비교가 결정적이지 않다. `KSResourceSyncManager.overlaps()` 가
    /// 이미 사용 중인 패턴과 동일하게 (a) 분리자 통일, (b) trailing slash 제거,
    /// (c) Windows 에서만 case-insensitive 비교를 위해 lowercased 처리한다.
    internal static func canonicalPathForContainsCheck(_ url: URL) -> String {
        var p = url.standardizedFileURL.path
            .replacingOccurrences(of: "\\", with: "/")
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        #if os(Windows)
            return p.lowercased()
        #else
            return p
        #endif
    }

    /// `dist/` 안에 패키저 출력(`output/`)이 위치할 때 dist 트리를 entry-by-entry
    /// 로 `dstResources/` 에 복사하면서 `output/` 서브트리 자체는 제외한다.
    /// 단순 `copyItem(dist→dstResources)` 가 출력 패키지를 자기 안으로 무한 재귀
    /// 복사하는 문제를 방지한다.
    private static func copyDistExcludingOutput(
        dist: URL,
        dstResources: URL,
        output: URL,
        fm: FileManager
    ) throws {
        if !fm.fileExists(atPath: dstResources.path) {
            try fm.createDirectory(at: dstResources, withIntermediateDirectories: true)
        }
        let outputStd = canonicalPathForContainsCheck(output)
        let entries = try fm.contentsOfDirectory(
            at: dist,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        for entry in entries {
            let entryStd = canonicalPathForContainsCheck(entry)
            if entryStd == outputStd || entryStd.hasPrefix(outputStd + "/") {
                continue  // skip the package output itself
            }
            let dst = dstResources.appendingPathComponent(entry.lastPathComponent)
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.copyItem(at: entry, to: dst)
        }
    }

    /// Windows 파일 잠금/공유 위반에 대한 짧은 backoff retry.
    /// 비-Windows 에서는 한 번만 시도한다.
    internal static func retryingTransient(
        attempts: Int = 3,
        delay: TimeInterval = 0.05,
        _ work: () throws -> Void
    ) throws {
        #if os(Windows)
            var lastError: (any Error)?
            for attempt in 0..<attempts {
                do {
                    try work()
                    return
                } catch let error as NSError where isTransientFileError(error) {
                    lastError = error
                    if attempt < attempts - 1 {
                        Thread.sleep(forTimeInterval: delay)
                    }
                }
            }
            if let lastError { throw lastError }
        #else
            try work()
        #endif
    }

    #if os(Windows)
        private static func isTransientFileError(_ error: NSError) -> Bool {
            // Win32 ERROR_SHARING_VIOLATION (32), ERROR_ACCESS_DENIED (5)
            // — Foundation 은 이를 NSPOSIXErrorDomain (EBUSY/EACCES) 또는
            // NSCocoaErrorDomain (NSFileWriteNoPermissionError) 로 노출한다.
            if error.domain == NSPOSIXErrorDomain {
                // EBUSY=16, EACCES=13 — ucrt errno 헤더 import 회피용 raw value.
                return error.code == 16 || error.code == 13
            }
            if error.domain == NSCocoaErrorDomain {
                return error.code == NSFileWriteNoPermissionError
                    || error.code == NSFileWriteFileExistsError
            }
            return false
        }
    #endif

    private static func copyTree(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.createDirectory(
            at: dst.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try fm.copyItem(at: src, to: dst)
    }

    /// Creates a `.zip` from `dir` using the `KSZipArchiver` (pure-Swift
    /// `ZIPFoundation`). Replaces the previous PowerShell shell-out — saves
    /// ~250 ms PowerShell cold-start per build and removes path-quoting
    /// vulnerabilities.
    ///
    /// Internal visibility lets tests call this helper directly.
    internal static func createZip(from dir: URL, to archive: URL) throws {
        try KSZipArchiver.zip(directory: dir, to: archive)
    }

    /// Async variant of `createZip(from:to:)` that suspends instead of
    /// blocking the calling thread on the (now in-process) compression work.
    internal static func createZipAsync(
        from dir: URL,
        to archive: URL
    ) async throws {
        try await KSZipArchiver.zipAsync(directory: dir, to: archive)
    }

    // MARK: - Fingerprint (RFC-002 §3.1)

    /// 패키지 산출물의 핵심 옵션 스냅샷. `<output>/.kalsae-pkg-fingerprint.json`
    /// 에 기록되어 다음 빌드의 incremental 가능 여부를 판단한다.
    /// 정책/아키텍처/exeName/icon/version/identifier 중 하나라도 바뀌면 stale
    /// 산출물(예: 이전 정책의 `webview2-runtime/`, 잘못된 아키텍처 DLL, 이전
    /// 이름의 exe/manifest, 이전 아이콘 파일) 이 남을 수 있어 output 전체를
    /// 재생성한다.
    internal struct Fingerprint: Codable, Equatable {
        let policy: String
        let architecture: String
        let exeName: String
        let iconName: String
        let version: String
        let identifier: String
        var standalone: Bool = false
        var installMode: String = ""
        // RFC-002 follow-up: strip 옵션 토글 시에도 fingerprint mismatch 로 자동
        // 전체 재생성. 미지정 시 false/[] 로 폴백되어 이전 빌드 schema 와도 호환.
        var stripSourceMaps: Bool = false
        var stripExtensions: [String] = []

        static func from(_ opts: Options) -> Fingerprint {
            Fingerprint(
                policy: opts.policy.rawValue,
                architecture: opts.architecture.rawValue,
                exeName: "\(opts.appName).exe",
                iconName: opts.iconPath?.lastPathComponent ?? "",
                version: opts.version,
                identifier: opts.identifier,
                standalone: opts.standalone,
                installMode: (opts.webView2InstallMode?.rawValue ?? effectiveInstallMode(opts).rawValue),
                stripSourceMaps: opts.stripSourceMaps,
                stripExtensions: opts.stripExtensions.sorted())
        }

        static func load(at url: URL) -> Fingerprint? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Fingerprint.self, from: data)
        }

        func write(to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url, options: [.atomic])
        }
    }
}
