/// `kalsae inspect` — 빌드 파생 값 (UpgradeCode 등)을 출력한다.
///
/// Tauri의 `tauri inspect` 미러. 현재는 `wix-upgrade-code` 서브명령만 제공.
import ArgumentParser
import Foundation
import KalsaeCLICore
import KalsaeCore

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Print build-derived values (UpgradeCode, etc.)",
        subcommands: [InspectWixUpgradeCodeCommand.self]
    )
}

struct InspectWixUpgradeCodeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wix-upgrade-code",
        abstract:
            "Print the deterministic MSI UpgradeCode for this project "
            + "(v5 UUID of `<productName>.exe.app.<arch>` in DNS namespace)."
    )

    @Option(name: .long, help: "Path to kalsae.json (default: ./kalsae.json).")
    var config: String? = nil

    @Option(
        name: .long,
        help: "Target architecture: x64 | arm64 | x86 (default: x64).")
    var arch: String = "x64"

    func run() throws {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let configURL =
            config.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
            ?? cwd.appendingPathComponent("kalsae.json")
        guard fm.fileExists(atPath: configURL.path) else {
            throw ValidationError(
                "kalsae.json not found at \(configURL.path) — pass --config explicitly.")
        }
        let data = try Data(contentsOf: configURL)
        let cfg = try JSONDecoder().decode(KSConfig.self, from: data)

        // 사용자가 windows.wix.upgradeCode를 명시했으면 그 값을 보여 준다.
        if let explicit = cfg.windowsBundle?.wix?.upgradeCode, !explicit.isEmpty {
            print(explicit)
            return
        }
        let uuid = KSUUIDv5.wixUpgradeCode(productName: cfg.app.name, arch: arch)
        print(KSUUIDv5.format(uuid))
    }
}
