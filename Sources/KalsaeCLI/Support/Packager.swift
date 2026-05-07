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
        public var iconPath: URL?  // .ico copied as-is when present
        public var vendorRuntimeRoot: URL?  // Vendor/WebView2/runtimes/<arch>/
        public var bootstrapperPath: URL?  // MicrosoftEdgeWebview2Setup.exe (optional)
        public var zip: Bool  // Create <output>.zip when true
        /// 패키징 시 소스맵(.map) 파일을 자동 제거한다.
        public var stripSourceMaps: Bool
        /// 패키징 시 추가로 제거할 파일 확장자 목록.
        public var stripExtensions: [String]

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
            iconPath: URL? = nil,
            vendorRuntimeRoot: URL? = nil,
            bootstrapperPath: URL? = nil,
            zip: Bool = false,
            stripSourceMaps: Bool = true,
            stripExtensions: [String] = []
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
            self.iconPath = iconPath
            self.vendorRuntimeRoot = vendorRuntimeRoot
            self.bootstrapperPath = bootstrapperPath
            self.zip = zip
            self.stripSourceMaps = stripSourceMaps
            self.stripExtensions = stripExtensions
        }
    }

    public struct Report: Sendable, CustomStringConvertible {
        public let outputPath: String
        public let zipPath: String?
        public let policy: String
        public let warnings: [String]

        public var description: String {
            var s = "Packaged \(policy) at \(outputPath)"
            if let z = zipPath { s += "\nArchive: \(z)" }
            for w in warnings { s += "\n  ! \(w)" }
            return s
        }
    }

    /// Runs packaging: file copy, manifest/runtime materialization,
    /// and optional zip archive creation.
    public static func run(_ opts: Options) throws -> Report {
        let fm = FileManager.default
        var warnings: [String] = []

        // Reset output directory.
        if fm.fileExists(atPath: opts.output.path) {
            try fm.removeItem(at: opts.output)
        }
        try fm.createDirectory(at: opts.output, withIntermediateDirectories: true)

        // 1) Executable
        let exeName = "\(opts.appName).exe"
        let dstExe = opts.output.appendingPathComponent(exeName)
        try fm.copyItem(at: opts.executablePath, to: dstExe)

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
        try fm.copyItem(at: opts.configPath, to: dstConfig)

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
            try copyTree(from: dist, to: dstResources)

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
            try fm.copyItem(at: icon, to: dst)
        }

        // 6) WebView2 runtime policy materialization
        var runtime: [String: Any] = [
            "policy": opts.policy.rawValue,
            "identifier": opts.identifier,
            "userDataFolder": "%LOCALAPPDATA%\\\(opts.identifier)\\WebView2",
        ]

        switch opts.policy {
        case .evergreen:
            try copyBootstrapper(
                opts: opts,
                warnings: &warnings)
        case .fixed:
            try copyFixedRuntime(
                opts: opts, runtime: &runtime,
                warnings: &warnings)
        case .auto:
            try copyBootstrapper(opts: opts, warnings: &warnings)
            try copyFixedRuntime(
                opts: opts, runtime: &runtime,
                warnings: &warnings)
        }

        let runtimeURL = opts.output.appendingPathComponent("kalsae.runtime.json")
        let runtimeData = try JSONSerialization.data(
            withJSONObject: runtime,
            options: [.prettyPrinted, .sortedKeys])
        try runtimeData.write(to: runtimeURL)

        // 7) Optional zip archive
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

        return Report(
            outputPath: opts.output.path,
            zipPath: zipPath,
            policy: opts.policy.rawValue,
            warnings: warnings)
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
        guard var root = try JSONSerialization.jsonObject(with: data, options: [])
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
        try out.write(to: url, options: [.atomic])
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
        try fm.copyItem(at: src, to: dst)
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
}
