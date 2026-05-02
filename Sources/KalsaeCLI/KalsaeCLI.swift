import ArgumentParser

/// 루트 명령. `new`, `dev`, `build` 서브명령으로 디스패치한다.
@main
struct KalsaeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "Kalsae",
        abstract: "Kalsae desktop-app project tooling.",
        version: "0.1.0",
        subcommands: [
            NewCommand.self,
            DevCommand.self,
            BuildCommand.self,
            DoctorCommand.self,
            GenerateCommand.self,
        ]
    )
}
