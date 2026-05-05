/// `KSPackager.runNSIS(_:)` — `KSNSISTemplate.render`로 .nsi를 만들고
/// `makensis`를 호출해 배포용 인스톨러 .exe를 생성한다.
import Foundation

extension KSPackager {
    public struct NSISReport: Sendable, CustomStringConvertible {
        public let scriptPath: String
        public let installerPath: String?
        public let warnings: [String]

        public var description: String {
            var s = "NSIS script written: \(scriptPath)"
            if let p = installerPath { s += "\nInstaller: \(p)" }
            for w in warnings { s += "\n  ! \(w)" }
            return s
        }
    }

    /// .nsi 스크립트를 sourceDir 옆 (`<sourceDir>/../<App>-installer.nsi`)에 만들고,
    /// PATH에 `makensis`가 있으면 컴파일까지 수행한다. 없으면 `installerPath`는
    /// nil이며 안내 warning이 채워진다.
    public static func runNSIS(_ opts: KSNSISTemplate.Options) throws -> NSISReport {
        let fm = FileManager.default
        var warnings: [String] = []

        let scriptDir = opts.sourceDir.deletingLastPathComponent()
        let scriptName = "\(opts.appName)-installer.nsi"
        let scriptURL = scriptDir.appendingPathComponent(scriptName)

        let body = KSNSISTemplate.render(opts)
        try body.write(to: scriptURL, atomically: false, encoding: .utf8)

        guard let makensis = findExecutable(named: "makensis") else {
            warnings.append(
                "makensis not found in PATH. Wrote .nsi script but skipped compilation. "
                    + "Install via `winget install NSIS.NSIS` or https://nsis.sourceforge.io/")
            return NSISReport(scriptPath: scriptURL.path, installerPath: nil, warnings: warnings)
        }

        // makensis는 cwd 기준으로 OutFile을 푼다.
        let proc = Process()
        proc.executableURL = makensis
        proc.arguments = ["/V2", scriptURL.path]
        proc.currentDirectoryURL = scriptDir
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            warnings.append("makensis exited with status \(proc.terminationStatus).")
            return NSISReport(scriptPath: scriptURL.path, installerPath: nil, warnings: warnings)
        }

        let installerName =
            opts.outputFileName
            ?? "\(opts.appName)-\(opts.version)-\(opts.architecture.rawValue)-Setup.exe"
        let installerURL = scriptDir.appendingPathComponent(installerName)
        let installerPath: String? =
            fm.fileExists(atPath: installerURL.path) ? installerURL.path : nil
        if installerPath == nil {
            warnings.append("Expected installer not found at \(installerURL.path).")
        }
        return NSISReport(
            scriptPath: scriptURL.path, installerPath: installerPath, warnings: warnings)
    }
}
