import Foundation
import Testing

@testable import KalsaeCore

// MARK: - kalsae.json: capabilities 블록 디코딩

@Suite("KSConfig — capabilities decoding")
struct KSCapabilitiesDecodingTests {

    @Test("Top-level capabilities + permissions decode from JSON")
    func decodeFromJSON() throws {
        let json = """
            {
              "app": { "identifier": "com.example.test", "name": "Test", "version": "1.0.0" },
              "build": { "frontendDist": "dist", "devServerURL": "http://localhost:5173" },
              "windows": [],
              "capabilities": {
                "permissions": [
                  {
                    "identifier": "fs:read",
                    "description": "Read files",
                    "commandsAllow": ["fs.readFile", "fs.exists"]
                  },
                  {
                    "identifier": "fs:write",
                    "commandsAllow": ["fs.writeFile"],
                    "commandsDeny": ["fs.writeFile.system"]
                  }
                ],
                "capabilities": [
                  {
                    "identifier": "main-window",
                    "windows": ["main"],
                    "permissions": ["fs:read"],
                    "platforms": ["windows", "macOS"]
                  }
                ]
              }
            }
            """
        let data = Data(json.utf8)
        let cfg = try JSONDecoder().decode(KSConfig.self, from: data)

        let caps = try #require(cfg.capabilities)
        #expect(caps.permissions.count == 2)
        #expect(caps.permissions[0].identifier == "fs:read")
        #expect(caps.permissions[0].commandsAllow == ["fs.readFile", "fs.exists"])
        #expect(caps.permissions[1].commandsDeny == ["fs.writeFile.system"])

        #expect(caps.capabilities.count == 1)
        let cap = caps.capabilities[0]
        #expect(cap.identifier == "main-window")
        #expect(cap.windows == ["main"])
        #expect(cap.permissions == ["fs:read"])
        #expect(cap.platforms == ["windows", "macOS"])
        #expect(cap.local == true)
    }

    @Test("Missing capabilities → nil")
    func missingCapabilities() throws {
        let json = """
            {
              "app": { "identifier": "x", "name": "X", "version": "1.0.0" },
              "build": { "frontendDist": "dist", "devServerURL": "http://localhost:5173" },
              "windows": []
            }
            """
        let cfg = try JSONDecoder().decode(KSConfig.self, from: Data(json.utf8))
        #expect(cfg.capabilities == nil)
    }

    @Test("isEmpty when neither permissions nor capabilities present")
    func isEmpty() {
        let empty = KSCapabilitiesConfig(permissions: [], capabilities: [])
        #expect(empty.isEmpty)

        let withPerm = KSCapabilitiesConfig(
            permissions: [KSPermission(identifier: "p")],
            capabilities: [])
        #expect(!withPerm.isEmpty)
    }
}
