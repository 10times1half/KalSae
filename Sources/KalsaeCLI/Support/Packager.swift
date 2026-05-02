/// SwiftPM 鍮뚮뱶 寃곌낵臾? ?꾨줎?몄뿏???먯뀑, ?ㅼ젙, ?몃?
/// 留ㅻ땲?섏뒪?몃? ?⑹퀜 ?щ같??媛?ν븳 ??踰덈뱾??鍮뚮뱶?쒕떎.
/// WebView2 ?뺤뇺???곕씪 WebView2 Evergreen 遺?몄뒪?몃옒???먮뒗
/// `Vendor/WebView2/runtimes/` ?섏쐞??怨좎젙 踰꾩쟾 ?고??꾩쓣 ?ы븿?쒕떎.
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
    }

    public struct Options: Sendable {
        public var projectRoot: URL
        public var executablePath: URL  // 蹂듭궗???ｌ쓣 鍮뚮뱶 ?꾨즺 .exe
        public var configPath: URL  // Kalsae.json
        public var frontendDist: URL?  // ?댁꽍??dist ?붾젆?곕━ (dev-server ?꾩슜 ?깆? nil 媛??
        public var output: URL  // dist/<name>-<version>-<arch>/
        public var appName: String
        public var version: String
        public var identifier: String
        public var architecture: Architecture
        public var policy: WebView2Policy
        public var iconPath: URL?  // .ico, 議댁옱 ??洹몃?濡?蹂듭궗
        public var vendorRuntimeRoot: URL?  // Vendor/WebView2/runtimes/<arch>/
        public var bootstrapperPath: URL?  // MicrosoftEdgeWebview2Setup.exe (?좏깮)
        public var zip: Bool  // true?대㈃ <output>.zip ?앹꽦

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
            zip: Bool = false
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
        }
    }

    public struct Report: Sendable, CustomStringConvertible {
        public let outputPath: String
        public let zipPath: String?
        public let policy: String
        public let warnings: [String]

        public var description: String {
            var s = "Packaged \(policy) ??\(outputPath)"
            if let z = zipPath { s += "\nArchive: \(z)" }
            for w in warnings { s += "\n  ! \(w)" }
            return s
        }
    }

    /// ?⑦궎吏 鍮뚮뱶瑜??ㅽ뻾?쒕떎. 二쇰줈 ?뚯씪 蹂듭궗, 留ㅻ땲?섏뒪???앹꽦,
    /// 諛?(?좏깮?? zip ?앹꽦?쇰줈 援ъ꽦?쒕떎. I/O ?ㅽ뙣 ???먮윭瑜??섏쭊??
    public static func run(_ opts: Options) throws -> Report {
        let fm = FileManager.default
        var warnings: [String] = []

        // 異쒕젰 ?붾젆?곕━ 珥덇린??
        if fm.fileExists(atPath: opts.output.path) {
            try fm.removeItem(at: opts.output)
        }
        try fm.createDirectory(at: opts.output, withIntermediateDirectories: true)

        // 1. ?ㅽ뻾 ?뚯씪.
        let exeName = "\(opts.appName).exe"
        let dstExe = opts.output.appendingPathComponent(exeName)
        try fm.copyItem(at: opts.executablePath, to: dstExe)

        // 2. ?ъ씠?쒖뭅 manifest (DPI ?몄떇, asInvoker).
        let manifestURL = opts.output.appendingPathComponent("\(exeName).manifest")
        try renderManifest(opts: opts).write(
            to: manifestURL,
            atomically: false,
            encoding: .utf8)

        // 3. Kalsae.json ?ㅼ젙.
        let dstConfig = opts.output.appendingPathComponent("Kalsae.json")
        try fm.copyItem(at: opts.configPath, to: dstConfig)

        // 4. ?꾨줎?몄뿏???먯궛.
        if let dist = opts.frontendDist, fm.fileExists(atPath: dist.path) {
            let dstResources = opts.output.appendingPathComponent("Resources")
            try copyTree(from: dist, to: dstResources)
        } else {
            warnings.append("Frontend dist directory not found; skipping Resources/.")
        }

        // 5. ?꾩씠肄?(?좏깮) ??MVP?먯꽌??PNG?묲CO 蹂???놁씠 洹몃?濡?蹂듭궗.
        if let icon = opts.iconPath, fm.fileExists(atPath: icon.path) {
            let dst = opts.output.appendingPathComponent(icon.lastPathComponent)
            try fm.copyItem(at: icon, to: dst)
        }

        // 6. WebView2 ?고????섏씠濡쒕뱶.
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

        // 7. ?좏깮???뺤텞.
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

    // MARK: - Manifest

    private static func renderManifest(opts: Options) -> String {
        // Win10+?먯꽌 ?몄떇?섎뒗 ?몃? manifest. PerMonitorV2 DPI ?몄떇怨?        // Common Controls v6 ?섏〈?깆쓣 異붽??섍퀬, UAC ?덈꺼? `asInvoker`濡?        // ?먯뼱 ?쇰컲 ?ъ슜?먭? UAC ?놁씠 ?ㅽ뻾?????덈룄濡??쒕떎.
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

    /// Win32 `assemblyIdentity` / VERSIONINFO???꾩슂??    /// ?꾧꺽??4-?뚰듃 `a.b.c.d` ?뺤떇?쇰줈 semver??臾몄옄?댁쓣 ?뺢퇋?뷀븳??
    private static func normalizedVersion(_ raw: String) -> String {
        // ?욌룄 ??援щ텇 ?レ옄 ?묐몢留?痍⑦븯怨??꾨━由대━利??묐??щ뒗 ?쒓굅?쒕떎.
        let head =
            raw.split(
                separator: "-", maxSplits: 1,
                omittingEmptySubsequences: false
            ).first ?? "0"
        var parts = head.split(separator: ".").compactMap { Int($0) }
        while parts.count < 4 { parts.append(0) }
        return parts.prefix(4).map(String.init).joined(separator: ".")
    }

    // MARK: - WebView2 ?섏씠濡쒕뱶 ?ы띁

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

    // MARK: - ?뚯씪?쒖뒪???ы띁

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

    /// `dir`??`.zip` ?꾩뭅?대툕瑜??앹꽦?쒕떎. Windows 10+?먯꽌 湲곕낯 ?쒓났?섎뒗
    /// PowerShell??`[System.IO.Compression.ZipFile]`???ъ슜?섎?濡?    /// ?쒕뱶?뚰떚 zip ?섏〈?깆씠 ?꾩슂 ?녿떎.
    ///
    /// **蹂댁븞:** ?뚯뒪? ???寃쎈줈???섍꼍 蹂?섎? ?듯빐 ?꾨떖?섎ŉ
    /// (PowerShell 紐낅졊??臾몄옄??蹂닿컙?쇰줈 ?쎌엯?섏? ?딆쓬)
    /// ?댁? ?곗샂?? 諛깊떛, ?щ윭, 湲고? PowerShell 硫뷀? 臾몄옄媛 ?ы븿??    /// 寃쎈줈媛 ?ㅽ겕由쏀듃瑜?源④굅??紐낅졊??二쇱엯?????녿떎.
    ///
    /// ?뚯뒪?멸? ?꾩껜 `run(_:)` ?뚯씠?꾨씪???놁씠 吏곸젒 ?寃잜븷 ???덈룄濡?    /// internal濡??좎??쒕떎.
    internal static func createZip(from dir: URL, to archive: URL) throws {
        let p = Self.makeZipProcess(from: dir, to: archive)
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw NSError(
                domain: "KSPackager", code: Int(p.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Compress-Archive exited \(p.terminationStatus)"
                ])
        }
    }

    /// Async variant of `createZip(from:to:)` that suspends instead of
    /// blocking the calling thread on `Process.waitUntilExit()`.
    /// Resumes once PowerShell exits via `terminationHandler`.
    internal static func createZipAsync(
        from dir: URL,
        to archive: URL
    ) async throws {
        let p = Self.makeZipProcess(from: dir, to: archive)
        try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Void, any Error>) in
            p.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(
                        throwing: NSError(
                            domain: "KSPackager",
                            code: Int(proc.terminationStatus),
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Compress-Archive exited \(proc.terminationStatus)"
                            ]))
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
    private static func makeZipProcess(
        from dir: URL,
        to archive: URL
    ) -> Process {
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
            "-Command", script,
        ]
        var env = ProcessInfo.processInfo.environment
        env["KS_PKG_SRC"] = dir.path
        env["KS_PKG_DST"] = archive.path
        p.environment = env
        return p
    }
}
