import ArgumentParser
import Foundation
import KalsaeCLICore
import KalsaeCore

/// `kalsae generate ...` 그룹. `generate` 명령은 Kalsae 프로젝트에서
/// 코드 생성 작업을 수행한다. 현재는 `bindings` 서브커맨드만 포함한다.
struct GenerateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate code from your Kalsae project (TS bindings, etc.).",
        subcommands: [Bindings.self])

    /// `kalsae generate bindings` — Swift 소스에서 `@KSCommand` 매크로가
    /// 붙은 함수들을 찾아 TypeScript 바인딩 파일(`.ts`)을 자동 생성한다.
    /// 생성된 바인딩은 프론트엔드에서 네이티브 명령을 타입 세이프하게 호출하는
    /// 데 사용된다.
    struct Bindings: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "bindings",
            abstract: "Generate TypeScript bindings for @KSCommand functions.")

        /// 생성된 TypeScript 바인딩을 저장할 출력 경로.
        /// 지정하지 않으면 `<project>/src/lib/kalsae.gen.ts`가 기본값.
        @Option(
            name: [.long, .customShort("o")],
            help: "Output .ts file path. Defaults to <project>/src/lib/kalsae.gen.ts.")
        var out: String?

        /// Swift 소스 파일을 찾을 프로젝트 루트.
        /// 기본값은 현재 작업 디렉터리(CWD).
        @Option(
            name: .long,
            help: "Project root containing Sources/. Defaults to CWD.")
        var project: String?

        /// 생성된 바인딩 헤더에 포함될 모듈 이름.
        @Option(
            name: .long,
            help: "Module name embedded in the generated header.")
        var module: String = "Kalsae"

        /// 명시적으로 지정한 Swift 소스 파일 또는 디렉터리 경로 목록.
        /// 비어 있으면 `Sources/` 아래에서 재귀적으로 탐색한다.
        @Argument(help: "Optional explicit Swift source files / directories.")
        var inputs: [String] = []

        @Option(
            name: .long,
            help: "Capability/permission validation mode: strict | warn | off (default: warn).")
        var capabilityCheck: String = "warn"

        func run() throws {
            let fm = FileManager.default
            let root = URL(fileURLWithPath: project ?? fm.currentDirectoryPath)

            var files: [URL] = []
            if inputs.isEmpty {
                let sources = root.appendingPathComponent("Sources")
                files = KSBindingsGenerator.discoverSwiftFiles(under: sources)
                if files.isEmpty {
                    files = KSBindingsGenerator.discoverSwiftFiles(under: root)
                }
            } else {
                for p in inputs {
                    let u = URL(fileURLWithPath: p, relativeTo: root)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                        files.append(contentsOf: KSBindingsGenerator.discoverSwiftFiles(under: u))
                    } else {
                        files.append(u)
                    }
                }
            }

            let outURL: URL
            if let out {
                outURL = URL(fileURLWithPath: out, relativeTo: root)
            } else {
                outURL =
                    root
                    .appendingPathComponent("src")
                    .appendingPathComponent("lib")
                    .appendingPathComponent("kalsae.gen.ts")
            }

            let opts = KSBindingsGenerator.Options(
                sources: files, output: outURL, moduleName: module)
            let report = try KSBindingsGenerator.run(opts)
            print(report.description)

            try runCapabilityValidation(root: root, files: files)
        }

        private func runCapabilityValidation(root: URL, files: [URL]) throws {
            guard let mode = KSCapabilityValidator.Mode(rawValue: capabilityCheck) else {
                throw ValidationError(
                    "--capability-check must be one of: strict | warn | off. Got '\(capabilityCheck)'.")
            }
            if mode == .off { return }

            // capabilities는 kalsae.json에서 옵셔널로 로드한다. 파일이 없거나
            // 파싱 실패 시에는 명령 단위 검증만 시도하기 위해 nil을 넘긴다.
            let fm = FileManager.default
            let capabilities: KSCapabilitiesConfig?
            if let cfgURL = KSConfigLocator.find(cwd: root, fm: fm) {
                capabilities = (try? KSConfigLoader.load(from: cfgURL))?.capabilities
            } else {
                capabilities = nil
            }

            let commands = KSBindingsGenerator.scanCommands(in: files)
            let vReport = KSCapabilityValidator.validate(
                capabilities: capabilities, commands: commands)

            if vReport.findings.isEmpty { return }
            print("🛡  capability validator findings:")
            for f in vReport.findings {
                print("   \(f.description)")
            }
            if vReport.shouldFail(in: mode) {
                throw ValidationError(
                    "Capability validation failed (mode: \(mode.rawValue)).")
            }
        }
    }
}
