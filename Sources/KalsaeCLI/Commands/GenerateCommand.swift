import ArgumentParser
import Foundation
import KalsaeCLICore

/// `kalsae generate ...` 그룹.
struct GenerateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate code from your Kalsae project (TS bindings, etc.).",
        subcommands: [Bindings.self])

    /// `kalsae generate bindings`
    struct Bindings: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "bindings",
            abstract: "Generate TypeScript bindings for @KSCommand functions.")

        @Option(name: [.long, .customShort("o")],
                help: "Output .ts file path. Defaults to <project>/src/lib/kalsae.gen.ts.")
        var out: String?

        @Option(name: .long,
                help: "Project root containing Sources/. Defaults to CWD.")
        var project: String?

        @Option(name: .long,
                help: "Module name embedded in the generated header.")
        var module: String = "Kalsae"

        @Argument(help: "Optional explicit Swift source files / directories.")
        var inputs: [String] = []

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
                outURL = root
                    .appendingPathComponent("src")
                    .appendingPathComponent("lib")
                    .appendingPathComponent("kalsae.gen.ts")
            }

            let opts = KSBindingsGenerator.Options(
                sources: files, output: outURL, moduleName: module)
            let report = try KSBindingsGenerator.run(opts)
            print(report.description)
        }
    }
}
