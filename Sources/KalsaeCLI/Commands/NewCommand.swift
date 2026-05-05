import ArgumentParser
import Foundation
/// `kalsae new <name>` scaffolds a new Kalsae project.
import KalsaeCLICore

struct NewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Scaffold a new Kalsae application."
    )

    enum FrontendPreset: String, ExpressibleByArgument, CaseIterable {
        case vanilla
        case react
        case vue
        case svelte
    }

    enum PackageManager: String, ExpressibleByArgument, CaseIterable {
        case npm
        case pnpm
        case yarn
    }

    enum IDEPreset: String, ExpressibleByArgument, CaseIterable {
        case vscode
    }

    @Argument(
        help:
            "Application name (used as the directory, target and window title). Optional when --name is given or --list is used."
    )
    var positionalName: String?

    @Option(
        name: [.customShort("n"), .long], help: "Application name. Wails-compatible alias for the positional argument.")
    var name: String?

    @Option(name: [.customShort("d"), .long], help: "Output directory (default: ./<name>).")
    var dir: String?

    @Flag(name: [.customShort("g"), .long], help: "Initialise a git repository in the new project.")
    var git: Bool = false

    @Flag(name: [.customShort("l"), .long], help: "List available frontend presets and exit.")
    var list: Bool = false

    @Flag(
        name: [.customShort("q"), .long],
        help: "Suppress progress output (errors and the final tree are still printed).")
    var quiet: Bool = false

    @Flag(name: [.customShort("f"), .long], help: "Overwrite the destination directory if it already exists.")
    var force: Bool = false

    @Option(name: .long, help: "Generate IDE configuration files. Supported: vscode.")
    var ide: IDEPreset?

    @Option(name: .long, help: "Frontend preset: vanilla | react | vue | svelte (default: vanilla).")
    var frontend: FrontendPreset = .vanilla

    @Option(name: .long, help: "Package manager for dev/build commands: npm | pnpm | yarn (default: npm).")
    var packageManager: PackageManager = .npm

    @Option(
        name: .long,
        help:
            "Use a local Kalsae checkout as a SwiftPM path dependency instead of fetching from GitHub. Useful while github.com/Kalsae/Kalsae is not yet published, or for local framework development."
    )
    var kalsaePath: String?

    @Flag(
        name: .long, inversion: .prefixedNo,
        help:
            "Run 'npm install' (or the chosen package manager) after scaffolding. Only applies to non-vanilla frontends."
    )
    var install: Bool = true

    @Flag(
        name: .long,
        help:
            "Use 'npm create vite@latest' to scaffold the frontend instead of bundled templates. Requires Node.js + npm. Only applies to react/vue/svelte frontends."
    )
    var useExternalScaffolder: Bool = false

    func run() throws {
        if list {
            printPresets()
            return
        }

        let resolvedName = try resolveName()

        let dest = try resolveDestination(name: resolvedName)

        let resolvedKalsaePath = try kalsaePath.map { raw -> String in
            let expanded = (raw as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("--kalsae-path '\(raw)' does not exist.")
            }
            let pkg = url.appendingPathComponent("Package.swift")
            guard FileManager.default.fileExists(atPath: pkg.path) else {
                throw ValidationError(
                    "--kalsae-path '\(raw)' does not contain a Package.swift — point this at a Kalsae checkout root."
                )
            }
            return url.path
        }

        let template = ProjectTemplate(
            name: resolvedName,
            frontend: frontend.rawValue,
            packageManager: packageManager.rawValue,
            kalsaePath: resolvedKalsaePath
        )

        // 외부 스캐폴더 경로 (옷인). vanilla은 대상 아님 — 항상 내장 템플릿 사용.
        if useExternalScaffolder, frontend != .vanilla {
            let parent = dest.deletingLastPathComponent()
            let scaffolder = KSExternalScaffolder(
                name: dest.lastPathComponent,
                frontend: frontend.rawValue,
                packageManager: packageManager.rawValue,
                kalsaePath: resolvedKalsaePath)
            log(
                "⚡  Scaffolding with 'npm create vite@latest \(dest.lastPathComponent)' (preset: \(frontend.rawValue))..."
            )
            do {
                try scaffolder.scaffold(in: parent)
            } catch {
                throw ValidationError("\(error)")
            }
        } else {
            try template.write(to: dest)
        }

        // 비-vanilla 프론트엔드: 의존성 설치 (디폴트 ON, --no-install 으로 스킵).
        if frontend != .vanilla, install {
            let pm = packageManager.rawValue
            if findExecutable(named: pm) != nil {
                log("📦  Running '\(pm) install' in \(dest.path)...")
                do {
                    try shell(command: pm, arguments: ["install"], in: dest.path)
                } catch {
                    log("⚠  '\(pm) install' failed: \(error). Run it manually before 'kalsae dev'.")
                }
            } else {
                log(
                    "⚠  '\(pm)' not found in PATH. Skipping install — run '\(pm) install' inside \(dest.lastPathComponent)/ before 'kalsae dev'."
                )
            }
        }

        if let ide {
            try writeIDEAssets(ide: ide, into: dest, name: resolvedName)
        }

        if git {
            try runGitInit(in: dest)
        }

        printSummary(name: resolvedName, dest: dest)
    }

    // MARK: - 헬퍼

    /// `--name`, 위치 인자, `--list` 의 우선순위와 충돌 검증.
    private func resolveName() throws -> String {
        switch (positionalName, name) {
        case (let p?, let n?) where p != n:
            throw ValidationError(
                "Conflicting names: positional '\(p)' vs --name '\(n)'. Provide only one.")
        case (let value?, _), (_, let value?):
            try validateName(value)
            return value
        default:
            throw ValidationError(
                "Missing application name. Pass it positionally ('kalsae new MyApp') or via --name.")
        }
    }

    private func validateName(_ value: String) throws {
        guard value.first?.isLetter == true,
            value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else {
            throw ValidationError(
                "'\(value)' is not a valid project name. Use letters, digits, hyphens or underscores, starting with a letter."
            )
        }
    }

    /// 출력 디렉터리 결정. 기존 디렉터리 존재 시 `--force`로만 허용.
    private func resolveDestination(name: String) throws -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let dest: URL = {
            if let dir, !dir.isEmpty {
                return URL(fileURLWithPath: dir, relativeTo: cwd).standardizedFileURL
            }
            return cwd.appendingPathComponent(name)
        }()

        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            if force {
                // 안전 가드: 비어있지 않은 디렉터리를 통째로 삭제하지 않고 내용만 비운다.
                let entries = (try? fm.contentsOfDirectory(atPath: dest.path)) ?? []
                for entry in entries {
                    try fm.removeItem(at: dest.appendingPathComponent(entry))
                }
                log("⚠  --force: cleared existing contents of \(dest.path)")
            } else {
                throw ValidationError(
                    "Directory '\(dest.path)' already exists. Pass --force to overwrite.")
            }
        }
        return dest
    }

    private func printPresets() {
        let frontends = FrontendPreset.allCases.map(\.rawValue).joined(separator: ", ")
        let pms = PackageManager.allCases.map(\.rawValue).joined(separator: ", ")
        let ides = IDEPreset.allCases.map(\.rawValue).joined(separator: ", ")
        print(
            """
            Available presets:
              --frontend         \(frontends)  (default: vanilla)
              --package-manager  \(pms)  (default: npm)
              --ide              \(ides)
            """)
    }

    private func writeIDEAssets(ide: IDEPreset, into dest: URL, name: String) throws {
        switch ide {
        case .vscode:
            let dir = dest.appendingPathComponent(".vscode")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let settings = """
                {
                  "swift.path": "",
                  "files.exclude": {
                    "**/.build": true,
                    "**/Package.resolved": false
                  }
                }
                """
            let launch = """
                {
                  "version": "0.2.0",
                  "configurations": [
                    {
                      "type": "lldb",
                      "request": "launch",
                      "name": "kalsae dev",
                      "program": "kalsae",
                      "args": ["dev"],
                      "cwd": "${workspaceFolder}"
                    },
                    {
                      "type": "lldb",
                      "request": "launch",
                      "name": "Debug \(name)",
                      "program": "${workspaceFolder}/.build/debug/\(name)",
                      "cwd": "${workspaceFolder}",
                      "preLaunchTask": "swift: Build Debug"
                    }
                  ]
                }
                """
            try settings.write(
                to: dir.appendingPathComponent("settings.json"),
                atomically: true, encoding: .utf8)
            try launch.write(
                to: dir.appendingPathComponent("launch.json"),
                atomically: true, encoding: .utf8)
            log("🧰  Wrote .vscode/ assets")
        }
    }

    private func runGitInit(in dest: URL) throws {
        guard findExecutable(named: "git") != nil else {
            log("⚠  git not found in PATH. Skipping git init.")
            return
        }
        log("🌱  Initialising git repository...")
        do {
            try shell(command: "git", arguments: ["init", "-q"], in: dest.path)
            try shell(command: "git", arguments: ["add", "-A"], in: dest.path)
            // 초기 커밋은 사용자 환경(user.name/email)에 따라 실패할 수 있으므로
            // 실패해도 워크플로를 막지 않는다.
            do {
                try shell(
                    command: "git",
                    arguments: ["commit", "-q", "-m", "Initial Kalsae scaffold"],
                    in: dest.path)
            } catch {
                log("⚠  Initial commit skipped: \(error)")
            }
        } catch {
            log("⚠  git init failed: \(error)")
        }
    }

    private func printSummary(name: String, dest: URL) {
        let cdTarget = relativeOrAbsolute(dest)
        let nextSteps: String
        switch frontend {
        case .vanilla:
            nextSteps = "cd \(cdTarget)\nkalsae dev"
        case .react, .vue, .svelte:
            let pm = packageManager.rawValue
            nextSteps =
                "cd \(cdTarget)\n"
                + (install ? "" : "\(pm) install\n")
                + "kalsae dev"
        }

        let tree = renderTree(name: name, frontend: frontend)

        print(
            """

            Created \(cdTarget)/

            \(tree)
            Next steps:
            \(nextSteps)

            """)
    }

    private func relativeOrAbsolute(_ url: URL) -> String {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        let std = url.standardizedFileURL
        let parent = std.deletingLastPathComponent()
        if parent.path == cwd.path {
            return std.lastPathComponent
        }
        return std.path
    }

    private func log(_ message: String) {
        if quiet { return }
        print(message)
    }

    /// 실제 스케폴딩된 파일 트리를 렌더링한다.
    private func renderTree(name: String, frontend: FrontendPreset) -> String {
        var lines: [String] = []
        lines.append("\(name)/")
        switch frontend {
        case .vanilla:
            lines.append("|- Package.swift")
            lines.append("`- Sources/\(name)/")
            lines.append("   |- App.swift")
            lines.append("   `- Resources/")
            lines.append("      |- kalsae.json")
            lines.append("      `- index.html")
        case .react:
            lines.append("|- Package.swift")
            lines.append("|- package.json")
            lines.append("|- vite.config.ts")
            lines.append("|- tsconfig.json")
            lines.append("|- tsconfig.node.json")
            lines.append("|- index.html")
            lines.append("|- .gitignore")
            lines.append("|- src/")
            lines.append("|  |- main.tsx")
            lines.append("|  |- App.tsx")
            lines.append("|  `- index.css")
            lines.append("`- Sources/\(name)/")
            lines.append("   |- App.swift")
            lines.append("   `- Resources/")
            lines.append("      `- kalsae.json")
        case .vue:
            lines.append("|- Package.swift")
            lines.append("|- package.json")
            lines.append("|- vite.config.ts")
            lines.append("|- tsconfig.json")
            lines.append("|- tsconfig.app.json")
            lines.append("|- tsconfig.node.json")
            lines.append("|- index.html")
            lines.append("|- .gitignore")
            lines.append("|- src/")
            lines.append("|  |- main.ts")
            lines.append("|  |- App.vue")
            lines.append("|  `- style.css")
            lines.append("`- Sources/\(name)/")
            lines.append("   |- App.swift")
            lines.append("   `- Resources/")
            lines.append("      `- kalsae.json")
        case .svelte:
            lines.append("|- Package.swift")
            lines.append("|- package.json")
            lines.append("|- vite.config.ts")
            lines.append("|- tsconfig.json")
            lines.append("|- svelte.config.js")
            lines.append("|- index.html")
            lines.append("|- .gitignore")
            lines.append("|- src/")
            lines.append("|  |- main.ts")
            lines.append("|  |- App.svelte")
            lines.append("|  `- app.css")
            lines.append("`- Sources/\(name)/")
            lines.append("   |- App.swift")
            lines.append("   `- Resources/")
            lines.append("      `- kalsae.json")
        }
        return lines.joined(separator: "\n")
    }
}
