import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSUserScript & KSUserScriptWrapper")
struct KSUserScriptTests {

    // MARK: - Value type

    @Test("Decode supports defaults")
    func decodeDefaults() throws {
        let json = #"""
            {
              "id": "x",
              "source": "console.log('hi');",
              "origins": ["https://example.org"]
            }
            """#
        let s = try JSONDecoder().decode(KSUserScript.self, from: Data(json.utf8))
        #expect(s.id == "x")
        #expect(s.source == "console.log('hi');")
        #expect(s.path == nil)
        #expect(s.injectionTime == .documentStart)
        #expect(s.forMainFrameOnly == false)
        #expect(s.origins == ["https://example.org"])
    }

    @Test("Scope.permits is case-insensitive set membership")
    func scopePermits() {
        let scope = KSUserScriptsScope(
            allowOrigins: ["https://example.org", "https://*.foo.com"])
        #expect(scope.permits(originPattern: "https://example.org"))
        #expect(scope.permits(originPattern: " HTTPS://EXAMPLE.ORG "))
        #expect(scope.permits(originPattern: "https://*.foo.com"))
        #expect(!scope.permits(originPattern: "https://evil.example.org"))
        #expect(!scope.permits(originPattern: ""))
    }

    @Test("Scope.matchesURL uses KSHTTPScope glob")
    func scopeMatchesURL() {
        let scope = KSUserScriptsScope(allowOrigins: ["https://*.foo.com"])
        #expect(scope.matchesURL("https://api.foo.com/x"))
        #expect(scope.matchesURL("https://foo.com/x"))
        #expect(!scope.matchesURL("https://bar.com/x"))
    }

    // MARK: - Wrapper

    @Test("Wrap encodes origins as JSON literal and inlines body")
    func wrapBasics() {
        let s = KSUserScript(
            id: "a", source: "console.log(1);",
            injectionTime: .documentStart,
            origins: ["https://example.org"])
        let out = KSUserScriptWrapper.wrap(s, source: "console.log(1);")
        #expect(out.contains(#""https://example.org""#))
        #expect(out.contains("console.log(1);"))
        // origin guard helper present
        #expect(out.contains("__ks_match"))
    }

    @Test("Wrap escapes special string chars")
    func wrapEscapes() {
        let s = KSUserScript(
            id: "x", source: "x",
            origins: ["https://example.org\"; alert(1);//"])
        let out = KSUserScriptWrapper.wrap(s, source: "x")
        // The dangerous double-quote must be escaped, breaking the injection.
        #expect(out.contains(#"\""#))
        #expect(!out.contains(#""https://example.org"; alert(1);//""#))
    }

    @Test("Wrap selects documentEnd polyfill branch")
    func wrapDocumentEnd() {
        let s = KSUserScript(
            id: "x", source: "x",
            injectionTime: .documentEnd,
            origins: ["https://example.org"])
        let out = KSUserScriptWrapper.wrap(s, source: "x")
        #expect(out.contains("documentEnd"))
        #expect(out.contains("DOMContentLoaded"))
    }
}

@Suite("KSConfigLoader — security.userScripts validation")
struct KSUserScriptsValidationTests {

    private func decode(_ json: String) throws -> KSConfig {
        try KSConfigLoader.decode(Data(json.utf8))
    }

    private static let baseHeader = #"""
        "app": { "name": "Demo", "version": "0.1.0", "identifier": "dev.K.demo" },
        "build": { "frontendDist": "dist", "devServerURL": "http://localhost:5173" },
        "windows": [ { "label": "main", "title": "Demo", "width": 800, "height": 600 } ],
        """#

    @Test("allowOrigins=[] with scripts is rejected")
    func denyByDefault() {
        let json = #"""
            {
              \#(Self.baseHeader)
              "security": {
                "csp": "default-src 'self'",
                "userScripts": {
                  "allowOrigins": [],
                  "scripts": [
                    { "source": "x", "origins": ["https://example.org"] }
                  ]
                }
              }
            }
            """#
        #expect(throws: KSError.self) { try self.decode(json) }
    }

    @Test("Script origin must be in allowOrigins")
    func originSubset() {
        let json = #"""
            {
              \#(Self.baseHeader)
              "security": {
                "csp": "default-src 'self'",
                "userScripts": {
                  "allowOrigins": ["https://example.org"],
                  "scripts": [
                    { "source": "x", "origins": ["https://other.org"] }
                  ]
                }
              }
            }
            """#
        #expect(throws: KSError.self) { try self.decode(json) }
    }

    @Test("source and path are mutually exclusive")
    func sourceXorPath() {
        let json = #"""
            {
              \#(Self.baseHeader)
              "security": {
                "csp": "default-src 'self'",
                "userScripts": {
                  "allowOrigins": ["https://example.org"],
                  "scripts": [
                    { "source": "x", "path": "y.js", "origins": ["https://example.org"] }
                  ]
                }
              }
            }
            """#
        #expect(throws: KSError.self) { try self.decode(json) }
    }

    @Test("path traversal '..' is rejected")
    func pathTraversal() {
        let json = #"""
            {
              \#(Self.baseHeader)
              "security": {
                "csp": "default-src 'self'",
                "userScripts": {
                  "allowOrigins": ["https://example.org"],
                  "scripts": [
                    { "path": "../etc/passwd", "origins": ["https://example.org"] }
                  ]
                }
              }
            }
            """#
        #expect(throws: KSError.self) { try self.decode(json) }
    }

    @Test("Duplicate ids are rejected")
    func duplicateIDs() {
        let json = #"""
            {
              \#(Self.baseHeader)
              "security": {
                "csp": "default-src 'self'",
                "userScripts": {
                  "allowOrigins": ["https://example.org"],
                  "scripts": [
                    { "id": "a", "source": "x", "origins": ["https://example.org"] },
                    { "id": "a", "source": "y", "origins": ["https://example.org"] }
                  ]
                }
              }
            }
            """#
        #expect(throws: KSError.self) { try self.decode(json) }
    }

    @Test("Valid config decodes cleanly")
    func validDecodes() throws {
        let json = #"""
            {
              \#(Self.baseHeader)
              "security": {
                "csp": "default-src 'self'",
                "userScripts": {
                  "allowOrigins": ["https://example.org"],
                  "scripts": [
                    { "id": "boot", "source": "console.log('hi');", "origins": ["https://example.org"], "injectionTime": "documentEnd" }
                  ]
                }
              }
            }
            """#
        let cfg = try decode(json)
        #expect(cfg.security.userScripts.scripts.count == 1)
        #expect(cfg.security.userScripts.scripts[0].id == "boot")
        #expect(cfg.security.userScripts.scripts[0].injectionTime == .documentEnd)
    }

    @Test("Empty userScripts decodes to default-deny defaults")
    func emptyDefaults() throws {
        let json = #"""
            {
              \#(Self.baseHeader)
              "security": { "csp": "default-src 'self'" }
            }
            """#
        let cfg = try decode(json)
        #expect(cfg.security.userScripts.allowOrigins.isEmpty)
        #expect(cfg.security.userScripts.scripts.isEmpty)
    }
}
