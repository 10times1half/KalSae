/// `KSPackager.runWiX(_:)` — `KSWiXTemplate.render`로 `.wxs`를 만들고
/// `candle.exe` + `light.exe`를 호출해 배포용 `.msi`를 생성한다.
///
/// 다중 언어: `languages`가 둘 이상이면 `light.exe`를 언어별로 호출해
/// `<App>_<ver>_<arch>_<lang>.msi`를 여러 개 산출한다.
public import Foundation
public import KalsaeCore

extension KSPackager {
    public struct WiXReport: Sendable, CustomStringConvertible {
        public let scriptPath: String
        /// 산출된 `.msi` 절대 경로(언어별).
        public let installerPaths: [String]
        public let warnings: [String]
        /// 자동 생성된 (또는 설정으로 받은) UpgradeCode UUID.
        public let upgradeCode: String

        public var description: String {
            var s = "WiX script written: \(scriptPath)\n  UpgradeCode: \(upgradeCode)"
            for p in installerPaths { s += "\n  Installer: \(p)" }
            for w in warnings { s += "\n  ! \(w)" }
            return s
        }
    }

    public struct WiXOptions: Sendable {
        public var template: KSWiXTemplate.Options
        public var languages: [String]
        public var localePaths: [String: String]
        public var fragmentPaths: [URL]
        public var autoFetchWiX: Bool
        public var useLocalToolsDir: Bool
        public var projectRoot: URL

        public init(
            template: KSWiXTemplate.Options,
            languages: [String] = ["en-US"],
            localePaths: [String: String] = [:],
            fragmentPaths: [URL] = [],
            autoFetchWiX: Bool = true,
            useLocalToolsDir: Bool = false,
            projectRoot: URL
        ) {
            self.template = template
            self.languages = languages.isEmpty ? ["en-US"] : languages
            self.localePaths = localePaths
            self.fragmentPaths = fragmentPaths
            self.autoFetchWiX = autoFetchWiX
            self.useLocalToolsDir = useLocalToolsDir
            self.projectRoot = projectRoot
        }
    }

    /// `.wxs`를 sourceDir 옆에 만들고, candle/light가 사용 가능하면 컴파일까지 수행.
    public static func runWiX(_ opts: WiXOptions) throws -> WiXReport {
        let fm = FileManager.default
        var warnings: [String] = []

        let scriptDir = opts.template.sourceDir.deletingLastPathComponent()
        let scriptName = "\(opts.template.appName)-installer.wxs"
        let scriptURL = scriptDir.appendingPathComponent(scriptName)

        let body = try KSWiXTemplate.render(opts.template)
        try body.write(to: scriptURL, atomically: false, encoding: .utf8)

        // WiX tool 위치.
        let tools: KSWiXProvisioner.Result
        do {
            tools = try KSWiXProvisioner.ensure(
                projectRoot: opts.projectRoot,
                autoFetch: opts.autoFetchWiX,
                useLocalToolsDir: opts.useLocalToolsDir)
        } catch let e as ShellError {
            warnings.append("WiX toolchain unavailable: \(e). Wrote .wxs only.")
            return WiXReport(
                scriptPath: scriptURL.path,
                installerPaths: [],
                warnings: warnings,
                upgradeCode: KSUUIDv5.format(opts.template.upgradeCode))
        }

        let objDir = scriptDir.appendingPathComponent("\(opts.template.appName)-wix-obj")
        if fm.fileExists(atPath: objDir.path) {
            try? fm.removeItem(at: objDir)
        }
        try fm.createDirectory(at: objDir, withIntermediateDirectories: true)

        // 1) candle.exe — .wxs → .wixobj
        let mainObj = objDir.appendingPathComponent("\(opts.template.appName).wixobj")
        var candleArgs: [String] = [
            "-nologo",
            "-arch", candleArch(opts.template.architecture),
            "-ext", "WixUIExtension",
            "-ext", "WixUtilExtension",
        ]
        // 변수 정의 (Icon/Banner/Dialog 경로).
        if let icon = opts.template.iconPath {
            candleArgs.append(contentsOf: ["-dIconPath=\(icon.path)"])
        }
        if let banner = opts.template.bannerPath {
            candleArgs.append(contentsOf: ["-dBannerPath=\(banner.path)"])
        }
        if let dlg = opts.template.dialogImagePath {
            candleArgs.append(contentsOf: ["-dDialogImagePath=\(dlg.path)"])
        }
        candleArgs.append(contentsOf: ["-o", mainObj.path, scriptURL.path])

        // 추가 fragment .wxs들을 같이 컴파일.
        var fragmentObjs: [URL] = []
        for frag in opts.fragmentPaths {
            let fragObj =
                objDir
                .appendingPathComponent(frag.deletingPathExtension().lastPathComponent + ".wixobj")
            let argsFrag = [
                "-nologo",
                "-arch", candleArch(opts.template.architecture),
                "-ext", "WixUIExtension",
                "-ext", "WixUtilExtension",
                "-o", fragObj.path,
                frag.path,
            ]
            try shell(command: tools.candleURL.path, arguments: argsFrag, in: scriptDir.path)
            fragmentObjs.append(fragObj)
        }
        try shell(command: tools.candleURL.path, arguments: candleArgs, in: scriptDir.path)

        // 2) light.exe — .wixobj → .msi (언어별)
        var installerPaths: [String] = []
        for lang in opts.languages {
            let outName =
                "\(opts.template.appName)_\(opts.template.version)_\(opts.template.architecture.rawValue)_\(lang).msi"
            let msiURL = scriptDir.appendingPathComponent(outName)
            var lightArgs: [String] = [
                "-nologo",
                "-ext", "WixUIExtension",
                "-ext", "WixUtilExtension",
                "-cultures:\(lang)",
            ]
            if let loc = opts.localePaths[lang] {
                lightArgs.append(contentsOf: ["-loc", loc])
            }
            lightArgs.append(contentsOf: ["-spdb", "-o", msiURL.path, mainObj.path])
            for f in fragmentObjs { lightArgs.append(f.path) }
            do {
                try shell(command: tools.lightURL.path, arguments: lightArgs, in: scriptDir.path)
                if fm.fileExists(atPath: msiURL.path) {
                    installerPaths.append(msiURL.path)
                } else {
                    warnings.append("Expected installer not found at \(msiURL.path).")
                }
            } catch {
                warnings.append("light.exe failed for \(lang): \(error)")
            }
        }

        return WiXReport(
            scriptPath: scriptURL.path,
            installerPaths: installerPaths,
            warnings: warnings,
            upgradeCode: KSUUIDv5.format(opts.template.upgradeCode))
    }

    private static func candleArch(_ a: KSPackager.Architecture) -> String {
        switch a {
        case .x64: return "x64"
        case .arm64: return "arm64"
        case .x86: return "x86"
        }
    }
}
