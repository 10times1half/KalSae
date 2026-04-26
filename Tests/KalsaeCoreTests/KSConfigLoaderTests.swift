import Testing
import Foundation
@testable import KalsaeCore

@Suite("KSConfigLoader")
struct KSConfigLoaderTests {
    @Test("Decodes a minimal valid config")
    func minimalValid() throws {
        let json = #"""
        {
          "app": {
            "name": "Demo",
            "version": "0.1.0",
            "identifier": "dev.Kalsae.demo"
          },
          "build": {
            "frontendDist": "dist",
            "devServerURL": "http://localhost:5173"
          },
          "windows": [
            { "label": "main", "title": "Demo", "width": 800, "height": 600 }
          ],
          "security": {
            "csp": "default-src 'self'",
            "fs": { "allow": [], "deny": [] },
            "devtools": false
          }
        }
        """#
        let config = try KSConfigLoader.decode(Data(json.utf8))
        #expect(config.app.name == "Demo")
        #expect(config.windows.count == 1)
        #expect(config.windows[0].label == "main")
    }

    @Test("Rejects duplicate window labels")
    func duplicateLabels() {
        let json = #"""
        {
          "app": { "name": "D", "version": "0", "identifier": "x" },
          "build": { "frontendDist": "dist", "devServerURL": "x" },
          "windows": [
            { "label": "main", "title": "A", "width": 1, "height": 1 },
            { "label": "main", "title": "B", "width": 1, "height": 1 }
          ],
          "security": { "csp": "x", "fs": { "allow": [], "deny": [] }, "devtools": false }
        }
        """#
        #expect(throws: KSError.self) {
            try KSConfigLoader.decode(Data(json.utf8))
        }
    }

    @Test("Reports missing required keys")
    func missingKey() {
        let json = #"{"app": {"name": "D", "version": "0"}}"#
        #expect(throws: KSError.self) {
            try KSConfigLoader.decode(Data(json.utf8))
        }
    }
}
