import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSShellScope")
struct KSShellScopeTests {
    @Test("Default scope permits common safe schemes and denies others")
    func defaultPermitsSafeSchemes() {
        let scope = KSShellScope()
        #expect(scope.permitsScheme("http"))
        #expect(scope.permitsScheme("HTTPS"))
        #expect(scope.permitsScheme("mailto"))
        #expect(!scope.permitsScheme("file"))
        #expect(!scope.permitsScheme("javascript"))
        #expect(scope.showItemInFolder)
        #expect(scope.moveToTrash)
    }

    @Test("Empty scheme list denies every scheme")
    func emptySchemeListDeniesAll() {
        let scope = KSShellScope(openExternalSchemes: [])
        #expect(!scope.permitsScheme("https"))
        #expect(!scope.permitsScheme("http"))
    }

    @Test("nil scheme list permits any scheme")
    func nilSchemeListPermitsAll() {
        let scope = KSShellScope(openExternalSchemes: nil)
        #expect(scope.permitsScheme("https"))
        #expect(scope.permitsScheme("file"))
        #expect(scope.permitsScheme("custom-app"))
    }

    @Test("Decodes from JSON with explicit null scheme list")
    func decodesNullSchemeList() throws {
        let json = #"{"openExternalSchemes": null, "showItemInFolder": false, "moveToTrash": false}"#
        let scope = try JSONDecoder().decode(KSShellScope.self, from: Data(json.utf8))
        #expect(scope.openExternalSchemes == nil)
        #expect(scope.permitsScheme("anything"))
        #expect(!scope.showItemInFolder)
        #expect(!scope.moveToTrash)
    }

    @Test("Missing key falls back to safe defaults")
    func missingKeyUsesDefaults() throws {
        let json = "{}"
        let scope = try JSONDecoder().decode(KSShellScope.self, from: Data(json.utf8))
        #expect(scope.openExternalSchemes == ["http", "https", "mailto"])
        #expect(scope.showItemInFolder)
        #expect(scope.moveToTrash)
    }

    @Test("Embedded shell field round-trips inside KSSecurityConfig")
    func roundTripsInsideSecurity() throws {
        let json = #"""
            {
            "csp": "default-src 'self'",
            "shell": {
            "openExternalSchemes": ["https"],
            "showItemInFolder": true,
            "moveToTrash": false
            }
            }
            """#
        let sec = try JSONDecoder().decode(KSSecurityConfig.self, from: Data(json.utf8))
        #expect(sec.shell.openExternalSchemes == ["https"])
        #expect(sec.shell.showItemInFolder)
        #expect(!sec.shell.moveToTrash)
        #expect(!sec.shell.permitsScheme("http"))
    }
}
