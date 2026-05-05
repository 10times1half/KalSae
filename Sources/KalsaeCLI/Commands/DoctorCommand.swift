import ArgumentParser
import Foundation
/// `kalsae doctor` - 로컬 개발 환경과 프로젝트 구성을 점검한다.
import KalsaeCLICore
import KalsaeCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check common environment and project issues."
    )

    @Option(
        name: .long,
        help: "Override path to Kalsae.json (default: ./Kalsae.json or ./kalsae.json).")
    var config: String? = nil

    @Flag(name: .long, help: "Exit with non-zero status when warnings are detected.")
    var strict: Bool = false

    @Flag(name: .long, help: "Print machine-readable JSON output.")
    var json: Bool = false

    func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let report = KSDoctor.run(.init(projectRoot: cwd, configPath: config))

        if json {
            let payload = DoctorJSONOutput(
                project: cwd.path,
                infos: report.infos,
                warnings: report.warnings,
                hasWarnings: report.hasWarnings,
                nodeVersion: report.nodeVersion,
                npmVersion: report.npmVersion,
                osName: report.osName,
                osVersion: report.osVersion,
                architecture: report.architecture,
                swiftVersion: report.swiftVersion)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            guard let text = String(data: data, encoding: .utf8) else {
                throw ValidationError("Failed to encode doctor JSON output.")
            }
            print(text)
            if strict, report.hasWarnings {
                throw ExitCode.failure
            }
            return
        }

        print("🩺  Kalsae Doctor")
        print("    Project: \(cwd.path)")
        print("")
        print("System")
        print("  OS         : \(report.osName ?? "?") \(report.osVersion ?? "")")
        print("  Arch       : \(report.architecture ?? "?")")
        print("  Swift      : \(report.swiftVersion ?? "(not detected)")")
        print("  Node.js    : \(report.nodeVersion ?? "(not detected)")")
        print("  npm        : \(report.npmVersion ?? "(not detected)")")
        print("  Kalsae CLI : \(KSVersion.current)")
        print("")
        for info in report.infos {
            print("✅  \(info)")
        }

        if report.warnings.isEmpty {
            print("\nNo issues detected.")
            return
        }

        print("\n⚠️  Warnings")
        for warning in report.warnings {
            print("- \(warning)")
        }

        print("\nSuggested recovery commands:")
        print("  Remove-Item -Recurse -Force .build\\repositories\\swift-syntax-*")
        print("  swift package resolve --disable-dependency-cache")

        if strict {
            throw ValidationError("Doctor found \(report.warnings.count) warning(s).")
        }
    }

    private struct DoctorJSONOutput: Codable {
        let project: String
        let infos: [String]
        let warnings: [String]
        let hasWarnings: Bool
        let nodeVersion: String?
        let npmVersion: String?
        let osName: String?
        let osVersion: String?
        let architecture: String?
        let swiftVersion: String?
    }
}
