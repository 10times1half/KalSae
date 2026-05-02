public import Foundation
import KalsaeCore

public struct KSDoctorOptions: Sendable {
    public var projectRoot: URL
    public var configPath: String?

    public init(projectRoot: URL, configPath: String? = nil) {
        self.projectRoot = projectRoot
        self.configPath = configPath
    }
}

public struct KSDoctorReport: Sendable {
    public var infos: [String]
    public var warnings: [String]

    public init(infos: [String] = [], warnings: [String] = []) {
        self.infos = infos
        self.warnings = warnings
    }

    public var hasWarnings: Bool { !warnings.isEmpty }
}

public enum KSDoctor {
    public static func run(_ options: KSDoctorOptions) -> KSDoctorReport {
        let fm = FileManager.default
        var report = KSDoctorReport()

        let configURL = resolveConfigURL(options: options, fm: fm)
        let appConfig = loadConfigIfPresent(configURL: configURL, report: &report)

        if let appConfig, let configURL {
            checkFrontendDist(config: appConfig,
                              configURL: configURL,
                              report: &report,
                              fm: fm)
        }

        checkWebView2(projectRoot: options.projectRoot,
                      report: &report,
                      fm: fm)
        checkSwiftSyntaxCache(projectRoot: options.projectRoot,
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

    private static func checkFrontendDist(config: KSConfig,
                                          configURL: URL,
                                          report: inout KSDoctorReport,
                                          fm: FileManager) {
        let distURL = configURL.deletingLastPathComponent().appendingPathComponent(config.build.frontendDist)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: distURL.path, isDirectory: &isDir), isDir.boolValue else {
            report.warnings.append("Frontend dist directory not found: \(distURL.path)")
            return
        }

        let count = (try? fm.contentsOfDirectory(
            at: distURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]))?.count ?? 0
        if count == 0 {
            report.warnings.append("Frontend dist directory is empty: \(distURL.path)")
        } else {
            report.infos.append("Frontend dist is ready: \(distURL.path)")
        }
    }

    private static func checkWebView2(projectRoot: URL,
                                      report: inout KSDoctorReport,
                                      fm: FileManager) {
        #if os(Windows)
        let staticLib = projectRoot
            .appendingPathComponent("Vendor")
            .appendingPathComponent("WebView2")
            .appendingPathComponent("build")
            .appendingPathComponent("native")
            .appendingPathComponent("x64")
            .appendingPathComponent("WebView2LoaderStatic.lib")
        if fm.fileExists(atPath: staticLib.path) {
            report.infos.append("WebView2 static loader found: \(staticLib.path)")
        } else {
            report.warnings.append("WebView2 static loader missing: \(staticLib.path)")
            report.warnings.append("Run .\\Scripts\\fetch-webview2.ps1 from project root, or pass -ProjectRoot to script.")
        }
        #else
        report.infos.append("WebView2 check skipped on non-Windows platform.")
        #endif
    }

    private static func checkSwiftSyntaxCache(projectRoot: URL,
                                              report: inout KSDoctorReport,
                                              fm: FileManager) {
        let repositories = projectRoot.appendingPathComponent(".build").appendingPathComponent("repositories")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: repositories.path, isDirectory: &isDir), isDir.boolValue else {
            report.infos.append("No local dependency cache at .build/repositories.")
            return
        }

        let children = (try? fm.contentsOfDirectory(
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
                  let text = try? String(contentsOf: gitConfig, encoding: .utf8) else {
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
