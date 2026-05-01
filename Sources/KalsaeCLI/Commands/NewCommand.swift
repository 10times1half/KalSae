import ArgumentParser
import Foundation
import KalsaeCLICore

/// `Kalsae new <name>` — 새 Kalsae 앱을 스케폴딩한다.
struct NewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Scaffold a new Kalsae application."
    )

    @Argument(help: "Application name (used as the directory, target and window title).")
    var name: String

    func run() throws {
        // 기본 이름 검증 — Swift 식별자 접두사로 적합해야 한다.
        guard name.first?.isLetter == true,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw ValidationError("'\(name)' is not a valid project name. Use letters, digits, hyphens or underscores, starting with a letter.")
        }

        let dest = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(name)

        guard !FileManager.default.fileExists(atPath: dest.path) else {
            throw ValidationError("Directory '\(name)' already exists.")
        }

        let template = ProjectTemplate(name: name)
        try template.write(to: dest)

        print("""

        ✔  Created \(name)/

           \(name)/
           ├── Package.swift
           └── Sources/\(name)/
               ├── App.swift
               └── Resources/
                   ├── Kalsae.json
                   └── index.html

        Next steps:
           cd \(name)
           Kalsae dev

        """)
    }
}
