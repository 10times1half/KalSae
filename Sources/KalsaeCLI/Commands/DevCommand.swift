import ArgumentParser
import Foundation
import KalsaeCLICore

/// `Kalsae dev` — build and run the project in development mode.
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
