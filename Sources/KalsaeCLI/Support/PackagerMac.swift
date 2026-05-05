/// macOS `.app` 번들 패키저. `KSPackager.runMac(_:)` 로 호출.
///
/// 디렉터리 구조:
///   <App>.app/Contents/
///     MacOS/<executable>
///     Resources/
///       Info.plist (NSHighResolutionCapable, NSAppTransportSecurity 기본값)
///       kalsae.json
///       <frontend dist...>
///       <icon>.icns (있을 때)
///
/// 코드사이닝/공증은 본 함수의 책임이 아니다 (`--codesign-identity` 같은
/// 후속 hook 으로 별도 처리). 인터페이스만 노출하고 실제 sign 호출은
/// 사용자 환경에 위임한다.
public import Foundation

extension KSPackager {
    public enum MacArchitecture: String, Sendable, CaseIterable {
        case arm64
        case x86_64
        case universal
    }

    public struct MacOptions: Sendable {
        public var executablePath: URL
        public var configPath: URL
        public var frontendDist: URL?
        public var output: URL  // dist/<App>-<ver>-<arch>/<App>.app
        public var appName: String
        public var version: String
        public var identifier: String
        public var architecture: MacArchitecture
        public var iconPath: URL?  // .icns
        public var minimumSystemVersion: String
        public var category: String  // LSApplicationCategoryType
        public var copyright: String?
        public var codesignIdentity: String?  // 인터페이스만 — 실제 호출은 후속 hook
        public var zip: Bool

        public init(
            executablePath: URL,
            configPath: URL,
            frontendDist: URL?,
            output: URL,
            appName: String,
            version: String,
            identifier: String,
            architecture: MacArchitecture,
            iconPath: URL? = nil,
            minimumSystemVersion: String = "14.0",
            category: String = "public.app-category.utilities",
            copyright: String? = nil,
            codesignIdentity: String? = nil,
            zip: Bool = false
        ) {
            self.executablePath = executablePath
            self.configPath = configPath
            self.frontendDist = frontendDist
            self.output = output
            self.appName = appName
            self.version = version
            self.identifier = identifier
            self.architecture = architecture
            self.iconPath = iconPath
            self.minimumSystemVersion = minimumSystemVersion
            self.category = category
            self.copyright = copyright
            self.codesignIdentity = codesignIdentity
            self.zip = zip
        }
    }

    public static func runMac(_ opts: MacOptions) throws -> Report {
        let fm = FileManager.default
        var warnings: [String] = []

        // <output>/<App>.app
        let bundleURL = opts.output.appendingPathComponent("\(opts.appName).app")
        if fm.fileExists(atPath: bundleURL.path) {
            try fm.removeItem(at: bundleURL)
        }
        let contents = bundleURL.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        // 1) Executable
        let dstExe = macOS.appendingPathComponent(opts.appName)
        try fm.copyItem(at: opts.executablePath, to: dstExe)
        // 실행 가능 비트 보존 (FileManager.copyItem이 보통 보존하지만 명시).
        #if os(macOS) || os(Linux)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstExe.path)
        #endif

        // 2) Info.plist
        let plistURL = contents.appendingPathComponent("Info.plist")
        try renderMacInfoPlist(opts: opts).write(
            to: plistURL, atomically: true, encoding: .utf8)

        // 3) Kalsae.json
        let dstConfig = resources.appendingPathComponent("Kalsae.json")
        try fm.copyItem(at: opts.configPath, to: dstConfig)

        // 4) Frontend dist
        if let dist = opts.frontendDist, fm.fileExists(atPath: dist.path) {
            // dist 내용을 Resources/ 직접 복사 (Resources/dist/ 이 아니라 Resources/index.html 식).
            try copyContents(of: dist, into: resources)
        } else {
            warnings.append("Frontend dist directory not found; .app will have no web assets.")
        }

        // 5) Icon (.icns)
        if let icon = opts.iconPath, fm.fileExists(atPath: icon.path) {
            let dst = resources.appendingPathComponent("AppIcon.icns")
            try fm.copyItem(at: icon, to: dst)
        }

        // 6) 코드사이닝 hook (인터페이스만)
        if let identity = opts.codesignIdentity, !identity.isEmpty {
            warnings.append(
                "Code signing identity '\(identity)' supplied but Kalsae does not invoke 'codesign' yet. Run it manually after packaging."
            )
        }

        // 7) Optional zip
        var zipPath: String? = nil
        if opts.zip {
            let archive = opts.output.deletingLastPathComponent()
                .appendingPathComponent("\(opts.appName)-\(opts.version)-\(opts.architecture.rawValue).zip")
            if fm.fileExists(atPath: archive.path) {
                try fm.removeItem(at: archive)
            }
            do {
                try createZipMac(from: bundleURL, to: archive)
                zipPath = archive.path
            } catch {
                warnings.append("Failed to create zip: \(error)")
            }
        }

        return Report(
            outputPath: bundleURL.path,
            zipPath: zipPath,
            policy: "macos-app",
            warnings: warnings)
    }

    private static func renderMacInfoPlist(opts: MacOptions) -> String {
        let copyright = opts.copyright ?? "Copyright © \(opts.appName)"
        let iconKey =
            opts.iconPath != nil
            ? "<key>CFBundleIconFile</key>\n    <string>AppIcon</string>\n    "
            : ""
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>CFBundleDevelopmentRegion</key>
                <string>en</string>
                <key>CFBundleExecutable</key>
                <string>\(opts.appName)</string>
                <key>CFBundleIdentifier</key>
                <string>\(opts.identifier)</string>
                <key>CFBundleInfoDictionaryVersion</key>
                <string>6.0</string>
                <key>CFBundleName</key>
                <string>\(opts.appName)</string>
                <key>CFBundleDisplayName</key>
                <string>\(opts.appName)</string>
                <key>CFBundlePackageType</key>
                <string>APPL</string>
                <key>CFBundleShortVersionString</key>
                <string>\(opts.version)</string>
                <key>CFBundleVersion</key>
                <string>\(opts.version)</string>
                <key>LSApplicationCategoryType</key>
                <string>\(opts.category)</string>
                <key>LSMinimumSystemVersion</key>
                <string>\(opts.minimumSystemVersion)</string>
                <key>NSHighResolutionCapable</key>
                <true/>
                <key>NSHumanReadableCopyright</key>
                <string>\(copyright)</string>
                \(iconKey)<key>NSPrincipalClass</key>
                <string>NSApplication</string>
            </dict>
            </plist>
            """
    }

    private static func copyContents(of src: URL, into dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        let entries = try fm.contentsOfDirectory(
            at: src, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for entry in entries {
            let target = dst.appendingPathComponent(entry.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.copyItem(at: entry, to: target)
        }
    }

    /// macOS/Linux에서 `ditto`(있을 때) 또는 `zip` CLI로 압축한다.
    /// Windows에서 호출되지 않으므로 `Compress-Archive`는 사용하지 않는다.
    internal static func createZipMac(from src: URL, to archive: URL) throws {
        #if os(Windows)
            // Windows에서는 .app 패키징 자체가 호출되지 않지만, 안전을 위해 fallback.
            try createZip(from: src.deletingLastPathComponent(), to: archive)
        #else
            let process = Process()
            // ditto는 macOS 표준; Linux 폴백은 zip.
            if FileManager.default.fileExists(atPath: "/usr/bin/ditto") {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-c", "-k", "--keepParent", src.path, archive.path]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.arguments = ["-r", "-q", archive.path, src.lastPathComponent]
                process.currentDirectoryURL = src.deletingLastPathComponent()
            }
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw NSError(
                    domain: "KSPackager", code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Archive exited \(process.terminationStatus)"])
            }
        #endif
    }
}
