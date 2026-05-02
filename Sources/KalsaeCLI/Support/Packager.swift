public import Foundation

/// SwiftPM 빌드 결과물, 프론트엔드 에셋, 설정, 외부
/// 매니페스트를 합쳐 재배포 가능한 앱 번들을 빌드한다.
/// WebView2 정쇝에 따라 WebView2 Evergreen 부트스트래퍼 또는
/// `Vendor/WebView2/runtimes/` 하위의 고정 버전 런타임을 포함한다.
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
            case .x64:   return "win-x64"
            case .arm64: return "win-arm64"
            case .x86:   return "win-x86"
            }
        }
    }

    public struct Options: Sendable {
        public var projectRoot: URL
        public var executablePath: URL          // 복사해 넣을 빌드 완료 .exe
        public var configPath: URL              // Kalsae.json
        public var frontendDist: URL?           // 해석된 dist 디렉터리 (dev-server 전용 앱은 nil 가능)
        public var output: URL                  // dist/<name>-<version>-<arch>/
        public var appName: String
        public var version: String
        public var identifier: String
        public var architecture: Architecture
        public var policy: WebView2Policy
        public var iconPath: URL?               // .ico, 존재 시 그대로 복사
        public var vendorRuntimeRoot: URL?      // Vendor/WebView2/runtimes/<arch>/
        public var bootstrapperPath: URL?       // MicrosoftEdgeWebview2Setup.exe (선택)
        public var zip: Bool                    // true이면 <output>.zip 생성

        public init(projectRoot: URL,
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
                    zip: Bool = false) {
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
        }
    }

    public struct Report: Sendable, CustomStringConvertible {
        public let outputPath: String
        public let zipPath: String?
        public let policy: String
        public let warnings: [String]

        public var description: String {
            var s = "Packaged \(policy) → \(outputPath)"
            if let z = zipPath { s += "\nArchive: \(z)" }
            for w in warnings { s += "\n  ! \(w)" }
            return s
        }
    }

    /// 패키지 빌드를 실행한다. 주로 파일 복사, 매니페스트 생성,
    /// 및 (선택적) zip 생성으로 구성된다. I/O 실패 시 에러를 던진다.
    public static func run(_ opts: Options) throws -> Report {
        let fm = FileManager.default
        var warnings: [String] = []

        // 출력 디렉터리 초기화.
        if fm.fileExists(atPath: opts.output.path) {
            try fm.removeItem(at: opts.output)
        }
        try fm.createDirectory(at: opts.output, withIntermediateDirectories: true)

        // 1. 실행 파일.
        let exeName = "\(opts.appName).exe"
        let dstExe = opts.output.appendingPathComponent(exeName)
        try fm.copyItem(at: opts.executablePath, to: dstExe)

        // 2. 사이드카 manifest (DPI 인식, asInvoker).
        let manifestURL = opts.output.appendingPathComponent("\(exeName).manifest")
        try renderManifest(opts: opts).write(to: manifestURL,
                                             atomically: false,
                                             encoding: .utf8)

        // 3. Kalsae.json 설정.
        let dstConfig = opts.output.appendingPathComponent("Kalsae.json")
        try fm.copyItem(at: opts.configPath, to: dstConfig)

        // 4. 프론트엔드 자산.
        if let dist = opts.frontendDist, fm.fileExists(atPath: dist.path) {
            let dstResources = opts.output.appendingPathComponent("Resources")
            try copyTree(from: dist, to: dstResources)
        } else {
            warnings.append("Frontend dist directory not found; skipping Resources/.")
        }

        // 5. 아이콘 (선택) — MVP에서는 PNG→ICO 변환 없이 그대로 복사.
        if let icon = opts.iconPath, fm.fileExists(atPath: icon.path) {
            let dst = opts.output.appendingPathComponent(icon.lastPathComponent)
            try fm.copyItem(at: icon, to: dst)
        }

        // 6. WebView2 런타임 페이로드.
        var runtime: [String: Any] = [
            "policy": opts.policy.rawValue,
            "identifier": opts.identifier,
            "userDataFolder": "%LOCALAPPDATA%\\\(opts.identifier)\\WebView2",
        ]

        switch opts.policy {
        case .evergreen:
            try copyBootstrapper(opts: opts,
                                 warnings: &warnings)
        case .fixed:
            try copyFixedRuntime(opts: opts, runtime: &runtime,
                                 warnings: &warnings)
        case .auto:
            try copyBootstrapper(opts: opts, warnings: &warnings)
            try copyFixedRuntime(opts: opts, runtime: &runtime,
                                 warnings: &warnings)
        }

        let runtimeURL = opts.output.appendingPathComponent("kalsae.runtime.json")
        let runtimeData = try JSONSerialization.data(
            withJSONObject: runtime,
            options: [.prettyPrinted, .sortedKeys])
        try runtimeData.write(to: runtimeURL)

        // 7. 선택적 압축.
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

        return Report(outputPath: opts.output.path,
                      zipPath: zipPath,
                      policy: opts.policy.rawValue,
                      warnings: warnings)
    }

    // MARK: - Manifest

    private static func renderManifest(opts: Options) -> String {
        // Win10+에서 인식하는 외부 manifest. PerMonitorV2 DPI 인식과
        // Common Controls v6 의존성을 추가하고, UAC 레벨은 `asInvoker`로
        // 두어 일반 사용자가 UAC 없이 실행할 수 있도록 한다.
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
          <assemblyIdentity
              type="win32"
              name="\(opts.identifier)"
              version="\(normalizedVersion(opts.version))"
              processorArchitecture="\(opts.architecture.rawValue)"/>
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

    /// Win32 `assemblyIdentity` / VERSIONINFO에 필요한
    /// 엄격한 4-파트 `a.b.c.d` 형식으로 semver식 문자열을 정규화한다.
    private static func normalizedVersion(_ raw: String) -> String {
        // 앞도 점 구분 숫자 접두만 취하고 프리릴리즈 접미사는 제거한다.
        let head = raw.split(separator: "-", maxSplits: 1,
                             omittingEmptySubsequences: false).first ?? "0"
        var parts = head.split(separator: ".").compactMap { Int($0) }
        while parts.count < 4 { parts.append(0) }
        return parts.prefix(4).map(String.init).joined(separator: ".")
    }

    // MARK: - WebView2 페이로드 헬퍼

    private static func copyBootstrapper(opts: Options,
                                         warnings: inout [String]) throws {
        guard let src = opts.bootstrapperPath else {
            warnings.append("No WebView2 Evergreen bootstrapper supplied; the app will rely on a system-installed runtime.")
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

    private static func copyFixedRuntime(opts: Options,
                                         runtime: inout [String: Any],
                                         warnings: inout [String]) throws {
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

    // MARK: - 파일시스템 헬퍼

    private static func copyTree(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.createDirectory(at: dst.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try fm.copyItem(at: src, to: dst)
    }

    /// `dir`의 `.zip` 아카이브를 생성한다. Windows 10+에서 기본 제공되는
    /// PowerShell의 `[System.IO.Compression.ZipFile]`을 사용하므로
    /// 서드파티 zip 의존성이 필요 없다.
    ///
    /// **보안:** 소스와 대상 경로는 환경 변수를 통해 전달되며
    /// (PowerShell 명령에 문자열 보간으로 삽입되지 않음)
    /// 담은 따옴표, 백틱, 달러, 기타 PowerShell 메타 문자가 포함된
    /// 경로가 스크립트를 깨거나 명령을 주입할 수 없다.
    ///
    /// 테스트가 전체 `run(_:)` 파이프라인 없이 직접 타겟할 수 있도록
    /// internal로 유지한다.
    internal static func createZip(from dir: URL, to archive: URL) throws {
        let p = Self.makeZipProcess(from: dir, to: archive)
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(domain: "KSPackager", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                                     "Compress-Archive exited \(p.terminationStatus)"])
        }
    }

    /// Async variant of `createZip(from:to:)` that suspends instead of
    /// blocking the calling thread on `Process.waitUntilExit()`.
    /// Resumes once PowerShell exits via `terminationHandler`.
    internal static func createZipAsync(from dir: URL,
                                        to archive: URL) async throws {
        let p = Self.makeZipProcess(from: dir, to: archive)
        try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Void, any Error>) in
            p.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: NSError(
                        domain: "KSPackager",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey:
                                   "Compress-Archive exited \(proc.terminationStatus)"]))
                }
            }
            do {
                try p.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    /// Builds the `Process` invocation shared by sync/async zip helpers.
    /// All untrusted path data is passed through environment variables,
    /// not interpolated into the PowerShell script.
    private static func makeZipProcess(from dir: URL,
                                       to archive: URL) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe")
        let script = """
        $ErrorActionPreference = 'Stop';
        Add-Type -AssemblyName System.IO.Compression.FileSystem;
        $src = $env:KS_PKG_SRC;
        $dst = $env:KS_PKG_DST;
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force; }
        [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $dst);
        """
        p.arguments = [
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-Command", script
        ]
        var env = ProcessInfo.processInfo.environment
        env["KS_PKG_SRC"] = dir.path
        env["KS_PKG_DST"] = archive.path
        p.environment = env
        return p
    }
}
