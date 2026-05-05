public import Foundation
import KalsaeCore

public struct KSDoctorOptions: Sendable {
    public var projectRoot: URL
    public var configPath: String?
    /// `true`이면 PATH 조회와 외부 프로세스 실행(node/npm 버전 캡처)을 건너뛴다.
    /// 단위 테스트가 호스트 환경에 의존하지 않도록 결정성을 보장하기 위한 옵션.
    public var skipExternalChecks: Bool

    public init(projectRoot: URL, configPath: String? = nil, skipExternalChecks: Bool = false) {
        self.projectRoot = projectRoot
        self.configPath = configPath
        self.skipExternalChecks = skipExternalChecks
    }
}
public struct KSDoctorReport: Sendable {
    public var infos: [String]
    public var warnings: [String]
    /// 감지된 Node.js 버전 문자열(예: `"v20.10.0"`). `node`가 PATH에 없거나
    /// 버전 캡처에 실패하면 `nil`. JSON 출력의 결정성을 위해 필드로 노출.
    public var nodeVersion: String?
    /// 감지된 npm 버전 문자열. 위와 동일 규칙.
    public var npmVersion: String?
    /// 호스트 OS 이름 (예: `"Windows"`, `"macOS"`, `"Linux"`).
    public var osName: String?
    /// 호스트 OS 버전 문자열 (예: `"10.0.22631"`).
    public var osVersion: String?
    /// 호스트 아키텍처 (`"x86_64"`, `"arm64"`, ...). `#if arch(...)` 기반.
    public var architecture: String?
    /// `swift --version` 의 첫 줄. 캡처 실패 시 `nil`.
    public var swiftVersion: String?

    public init(
        infos: [String] = [],
        warnings: [String] = [],
        nodeVersion: String? = nil,
        npmVersion: String? = nil,
        osName: String? = nil,
        osVersion: String? = nil,
        architecture: String? = nil,
        swiftVersion: String? = nil
    ) {
        self.infos = infos
        self.warnings = warnings
        self.nodeVersion = nodeVersion
        self.npmVersion = npmVersion
        self.osName = osName
        self.osVersion = osVersion
        self.architecture = architecture
        self.swiftVersion = swiftVersion
    }

    public var hasWarnings: Bool { !warnings.isEmpty }
}
public enum KSDoctor {
    public static func run(_ options: KSDoctorOptions) -> KSDoctorReport {
        let fm = FileManager.default
        var report = KSDoctorReport()

        let configURL = resolveConfigURL(options: options, fm: fm)
        _ = loadConfigIfPresent(configURL: configURL, report: &report)

        // 호스트 환경 정보 (Wails doctor 호환).
        captureHostEnvironment(report: &report)
        if !options.skipExternalChecks {
            captureSwiftVersion(report: &report)
        }

        // Node.js / npm 환경 점검 — Wails doctor와 동일하게 "환경 의존성"만
        // 다룬다. 빌드 산출물(frontendDist) 검증은 doctor의 책임이 아니므로
        // 제거됨. 필요한 경우 향후 `kalsae build --verify` 등으로 분리.
        if !options.skipExternalChecks {
            checkNode(projectRoot: options.projectRoot, report: &report, fm: fm)
            checkNpm(projectRoot: options.projectRoot, report: &report, fm: fm)
        }

        checkWebView2(
            projectRoot: options.projectRoot,
            report: &report,
            fm: fm)
        checkSwiftSyntaxCache(
            projectRoot: options.projectRoot,
            report: &report,
            fm: fm)

        return report
    }

    private static func resolveConfigURL(options: KSDoctorOptions, fm: FileManager) -> URL? {
        if let path = options.configPath {
            return URL(fileURLWithPath: path, relativeTo: options.projectRoot)
        }
        let upper = options.projectRoot.appendingPathComponent("Kalsae.json")
        if fm.fileExists(atPath: upper.path) { return upper }
        let lower = options.projectRoot.appendingPathComponent("kalsae.json")
        if fm.fileExists(atPath: lower.path) { return lower }
        return nil
    }

    private static func loadConfigIfPresent(configURL: URL?, report: inout KSDoctorReport) -> KSConfig? {
        guard let configURL else {
            report.warnings.append("Config file not found. Expected Kalsae.json or kalsae.json in project root.")
            return nil
        }
        do {
            let config = try KSConfigLoader.load(from: configURL)
            report.infos.append("Loaded config: \(configURL.path)")
            return config
        } catch {
            report.warnings.append("Failed to load \(configURL.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Node.js / npm

    /// PATH에서 `node`를 찾고 `--version` 출력을 캡처한다.
    /// 프로젝트 루트에 `package.json`이 있으면 부재 시 warning, 없으면 info.
    /// 메이저 버전이 18 미만이면 LTS 권장 warning을 추가한다.
    private static func checkNode(
        projectRoot: URL,
        report: inout KSDoctorReport,
        fm: FileManager
    ) {
        let needsNode = fm.fileExists(
            atPath: projectRoot.appendingPathComponent("package.json").path)

        guard let url = findExecutable(named: "node") else {
            let msg = "Node.js not found in PATH."
            if needsNode {
                report.warnings.append(
                    msg + " Required because package.json exists in project root.")
            } else {
                report.infos.append(msg + " Only required for non-vanilla frontends.")
            }
            return
        }

        guard let raw = captureVersion(at: url) else {
            report.warnings.append(
                "Detected node at \(url.path) but failed to capture --version output.")
            return
        }

        report.nodeVersion = raw
        if let major = parseSemverMajor(raw), major < 18 {
            report.warnings.append(
                "Node.js \(raw) is older than the recommended LTS (>= 18). Consider upgrading.")
        } else {
            report.infos.append("Node.js \(raw) detected at \(url.path).")
        }
    }

    /// PATH에서 `npm`을 찾고 `--version`을 캡처한다.
    private static func checkNpm(
        projectRoot: URL,
        report: inout KSDoctorReport,
        fm: FileManager
    ) {
        let needsNpm = fm.fileExists(
            atPath: projectRoot.appendingPathComponent("package.json").path)

        guard let url = findExecutable(named: "npm") else {
            let msg = "npm not found in PATH."
            if needsNpm {
                report.warnings.append(
                    msg + " Required because package.json exists in project root.")
            } else {
                report.infos.append(msg + " Only required for non-vanilla frontends.")
            }
            return
        }

        guard let raw = captureVersion(at: url) else {
            report.warnings.append(
                "Detected npm at \(url.path) but failed to capture --version output.")
            return
        }
        report.npmVersion = raw
        report.infos.append("npm \(raw) detected at \(url.path).")
    }

    // MARK: - Host environment

    /// OS / 아키텍처 정보를 채운다. 외부 프로세스를 실행하지 않으므로
    /// `skipExternalChecks` 와 무관하게 항상 호출된다.
    private static func captureHostEnvironment(report: inout KSDoctorReport) {
        #if os(Windows)
            report.osName = "Windows"
        #elseif os(macOS)
            report.osName = "macOS"
        #elseif os(Linux)
            report.osName = "Linux"
        #elseif os(iOS)
            report.osName = "iOS"
        #elseif os(Android)
            report.osName = "Android"
        #else
            report.osName = "Unknown"
        #endif

        let v = ProcessInfo.processInfo.operatingSystemVersion
        report.osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"

        #if arch(x86_64)
            report.architecture = "x86_64"
        #elseif arch(arm64)
            report.architecture = "arm64"
        #elseif arch(i386)
            report.architecture = "i386"
        #elseif arch(arm)
            report.architecture = "arm"
        #else
            report.architecture = "unknown"
        #endif
    }

    /// `swift --version` 의 첫 줄을 캡처해 `report.swiftVersion`에 채운다.
    private static func captureSwiftVersion(report: inout KSDoctorReport) {
        guard let url = findExecutable(named: "swift") else { return }
        report.swiftVersion = captureVersion(at: url)
    }

    /// `<exe> --version`을 실행해 stdout 첫 줄을 트리밍하여 반환한다.
    /// Windows의 `.cmd`/`.bat` (npm 등)는 PowerShell `&` call 연산자로 래핑한다
    /// — `cmd /c`는 `C:\Program Files\...\npm.cmd`처럼 공백 포함 경로를 안정적으로
    /// 인용하기 어렵기 때문.
    private static func captureVersion(at url: URL) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        #if os(Windows)
            let ext = url.pathExtension.lowercased()
            if ext == "cmd" || ext == "bat" {
                let psURL =
                    findExecutable(named: "pwsh") ?? findExecutable(named: "powershell")
                guard let psURL else { return nil }
                process.executableURL = psURL
                let escaped = url.path.replacingOccurrences(of: "'", with: "''")
                process.arguments = [
                    "-NoProfile", "-ExecutionPolicy", "Bypass",
                    "-Command", "& '\(escaped)' --version",
                ]
            } else {
                process.executableURL = url
                process.arguments = ["--version"]
            }
        #else
            process.executableURL = url
            process.arguments = ["--version"]
        #endif

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let first =
            text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? text
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `v20.10.0` 또는 `10.2.5` 형태에서 메이저 정수만 추출한다.
    private static func parseSemverMajor(_ raw: String) -> Int? {
        var s = Substring(raw)
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        let head = s.prefix(while: { $0.isNumber })
        return Int(head)
    }

    private static func checkWebView2(
        projectRoot: URL,
        report: inout KSDoctorReport,
        fm: FileManager
    ) {
        #if os(Windows)
            let headerFile =
                projectRoot
                .appendingPathComponent("Vendor")
                .appendingPathComponent("WebView2")
                .appendingPathComponent("build")
                .appendingPathComponent("native")
                .appendingPathComponent("include")
                .appendingPathComponent("WebView2.h")
            if fm.fileExists(atPath: headerFile.path) {
                report.infos.append("WebView2 SDK headers found: \(headerFile.path)")
            } else {
                report.warnings.append("WebView2 SDK headers missing: \(headerFile.path)")
                report.warnings.append(
                    "Run .\\Scripts\\fetch-webview2.ps1 from project root, or pass -ProjectRoot to script.")
            }
        #else
            report.infos.append("WebView2 check skipped on non-Windows platform.")
        #endif
    }

    private static func checkSwiftSyntaxCache(
        projectRoot: URL,
        report: inout KSDoctorReport,
        fm: FileManager
    ) {
        let repositories = projectRoot.appendingPathComponent(".build").appendingPathComponent("repositories")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: repositories.path, isDirectory: &isDir), isDir.boolValue else {
            report.infos.append("No local dependency cache at .build/repositories.")
            return
        }

        let children =
            (try? fm.contentsOfDirectory(
                at: repositories,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])) ?? []
        let swiftSyntaxDirs = children.filter { $0.lastPathComponent.hasPrefix("swift-syntax-") }
        if swiftSyntaxDirs.isEmpty {
            report.infos.append("No swift-syntax cache directory detected.")
            return
        }

        for dir in swiftSyntaxDirs {
            let gitConfig = dir.appendingPathComponent(".git").appendingPathComponent("config")
            guard fm.fileExists(atPath: gitConfig.path),
                let text = try? String(contentsOf: gitConfig, encoding: .utf8)
            else {
                report.warnings.append("swift-syntax cache may be incomplete: \(dir.lastPathComponent)")
                continue
            }

            if text.contains("url = https://github.com/swiftlang/swift-syntax.git") {
                report.infos.append("swift-syntax cache remote is configured: \(dir.lastPathComponent)")
            } else {
                report.warnings.append("swift-syntax cache remote looks invalid: \(dir.lastPathComponent)")
            }
        }
    }
}
