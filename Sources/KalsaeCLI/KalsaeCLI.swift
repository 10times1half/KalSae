import ArgumentParser

/// Root command. Dispatches to `new`, `dev`, or `build` subcommands.
@main
struct KalsaeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "Kalsae",
        abstract: "Kalsae desktop-app project tooling.",
        version: "0.1.0",
        subcommands: [NewCommand.self, DevCommand.self, BuildCommand.self, GenerateCommand.self]
    )
}
