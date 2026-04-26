import Testing
import Foundation
@testable import KalsaeCore

/// Validates that the repo's sample config parses and validates cleanly.
@Suite("Sample config")
struct KSSampleConfigTests {
    @Test("Examples/kalsae.sample.json parses and validates")
    func sampleParses() throws {
        let url = sampleURL()
        let config = try KSConfigLoader.load(from: url)
        #expect(config.app.identifier == "dev.kalsae.demo")
        #expect(config.windows.first?.label == "main")
        #expect(config.security.devtools == true)
    }

    @Test("commandAllowlist is carried through decode")
    func allowlist() throws {
        let json = #"""
        {
          "app": { "name": "D", "version": "0", "identifier": "x" },
          "build": { "frontendDist": "d", "devServerURL": "x" },
          "windows": [
            { "label": "main", "title": "A", "width": 100, "height": 100 }
          ],
          "security": { "commandAllowlist": ["a", "b"] }
        }
        """#
        let cfg = try KSConfigLoader.decode(Data(json.utf8))
        #expect(cfg.security.commandAllowlist == ["a", "b"])
    }

    private func sampleURL() -> URL {
        // Tests run from the package root; resolve Examples relative to it.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return cwd.appendingPathComponent("Examples/kalsae.sample.json")
    }
}
