import ArgumentParser
import Foundation
import KalsaeCLICore
import KalsaeCore

/// `kalsae doctor` — 로컬 개발 환경(Kalsae CLI, Swift, Node.js 등)과
/// 프로젝트 구성(kalsae.json)의 이상 유무를 진단한다.
struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check common environment and project issues."
    )

    /// kalsae.json 경로 재정의 (기본값: ./kalsae.json).
    @Option(
        name: .long,
        help: "Override path to kalsae.json (default: ./kalsae.json).")
    var config: String? = nil

    /// 경고가 하나라도 있으면 종료 코드를 0이 아닌 값으로 반환한다.
    @Flag(name: .long, help: "Exit with non-zero status when warnings are detected.")
    var strict: Bool = false

    /// 기계가 읽기 쉬운 JSON 형식으로 진단 결과를 출력한다.
    @Flag(name: .long, help: "Print machine-readable JSON output.")
    var json: Bool = false

    /// 특정 배포 대상(dev / devid / mas / win-store / ios-appstore)에 필요한
    /// 도구와 환경이 갖춰져 있는지 함께 검사한다.
    @Option(
        name: .long,
        help: "Check tooling for a distribution target: dev | devid | mas | win-store | ios-appstore.")
    var store: String? = nil

    func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resolvedStore: KSDistributionTarget? = {
            guard let raw = store, !raw.isEmpty else { return nil }
            return KSDistributionTarget.parse(raw)
        }()
        if let raw = store, !raw.isEmpty, resolvedStore == nil {
            throw ValidationError(
                "--store must be one of: dev | devid | mas | win-store | ios-appstore "
                    + "(got '\(raw)').")
        }
        let report = KSDoctor.run(
            .init(
                projectRoot: cwd,
                configPath: config,
                distributionTarget: resolvedStore))

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

    /// JSON 출력용 Codable 모델. `--json` 플래그가 지정되었을 때
    /// `KSDoctor.Report`의 내용을 직렬화하는 데 사용된다.
    private struct DoctorJSONOutput: Codable {
        /// 프로젝트 루트 절대 경로.
        let project: String
        /// 정보성 메시지 목록.
        let infos: [String]
        /// 경고 메시지 목록.
        let warnings: [String]
        /// 경고가 하나라도 존재하는지 여부 (`--strict` 검사용).
        let hasWarnings: Bool
        /// 감지된 Node.js 버전 (없으면 nil).
        let nodeVersion: String?
        /// 감지된 npm 버전 (없으면 nil).
        let npmVersion: String?
        /// 운영체제 이름 (예: "Windows", "macOS").
        let osName: String?
        /// 운영체제 버전.
        let osVersion: String?
        /// CPU 아키텍처 (예: "x86_64", "arm64").
        let architecture: String?
        /// Swift 버전 문자열 (예: "6.0.3").
        let swiftVersion: String?
    }
}
