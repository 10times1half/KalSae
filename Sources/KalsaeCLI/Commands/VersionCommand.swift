import ArgumentParser
import Foundation
import KalsaeCore

/// `kalsae version` — Kalsae CLI 버전을 출력한다 (Wails 호환).
/// `--version` 옵션과 동일한 결과를 별도 서브커맨드로도 제공한다.
struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the Kalsae CLI version."
    )

    @Flag(name: .long, help: "Print machine-readable JSON output.")
    var json: Bool = false

    func run() throws {
        if json {
            let payload = ["version": KSVersion.current]
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }
        print(KSVersion.current)
    }
}
