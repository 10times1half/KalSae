import ArgumentParser
import Foundation
/// `Kalsae new <name>` ????Kalsae ?깆쓣 ?ㅼ??대뵫?쒕떎.
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

    @Argument(help: "Application name (used as the directory, target and window title).")
    var name: String

    @Option(name: .long, help: "Frontend preset: vanilla | react | vue | svelte (default: vanilla).")
    var frontend: FrontendPreset = .vanilla

    @Option(name: .long, help: "Package manager for dev/build commands: npm | pnpm | yarn (default: npm).")
    var packageManager: PackageManager = .npm

    func run() throws {
        guard name.first?.isLetter == true,
            name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else {
            throw ValidationError(
                "'\(name)' is not a valid project name. Use letters, digits, hyphens or underscores, starting with a letter."
            )
        }

        let dest = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(name)

        guard !FileManager.default.fileExists(atPath: dest.path) else {
            throw ValidationError("Directory '\(name)' already exists.")
        }

        let template = ProjectTemplate(
            name: name,
            frontend: frontend.rawValue,
            packageManager: packageManager.rawValue
        )
        try template.write(to: dest)

        print(
            """

            ?? Created \(name)/

            \(name)/
            ?쒋?? Package.swift
            ?붴?? Sources/\(name)/
            ?쒋?? App.swift
            ?붴?? Resources/
            ?쒋?? Kalsae.json
            ?붴?? index.html

            Next steps:
            cd \(name)
            Kalsae dev

            """)
    }
}
