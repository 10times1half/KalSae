import ArgumentParser
import Foundation
import KalsaeCLICore

/// `Kalsae dev` — 개발 모드로 프로젝트를 빌드하고 실행한다.
struct DevCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dev",
        abstract: "Build and run the project in development mode."
    )

    @Option(name: .shortAndLong, help: "Executable target to run (required when Package.swift has multiple executables).")
    var target: String? = nil

    func run() throws {
        var args = ["run"]
        if let t = target { args += [t] }
        print("▶  swift \(args.joined(separator: " "))")
        try shell(command: "swift", arguments: args)
    }
}
