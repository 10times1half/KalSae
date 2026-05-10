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

    // MARK: - RFC-002 §2.1 — fsScope 필드

    @Test("fsScope key absent → default-deny empty scope (RFC-002 §2.1)")
    func fsScopeMissingKeyDeniesAll() throws {
        // 기존 설정 파일은 `fsScope` 키가 없을 수 있다. 이 경우 `KSFSScope()`
        // 기본값(빈 allow/deny)이 사용되어 모든 경로가 거부되어야 한다.
        let json = "{}"
        let scope = try JSONDecoder().decode(KSShellScope.self, from: Data(json.utf8))
        #expect(scope.fsScope.allow.isEmpty)
        #expect(scope.fsScope.deny.isEmpty)
        let ctx = KSFSScope.ExpansionContext(
            app: "/app", home: "/home/user", docs: "/home/user/Documents", temp: "/tmp")
        #expect(!scope.fsScope.permits(absolutePath: "/etc/passwd", in: ctx))
        #expect(!scope.fsScope.permits(absolutePath: "/home/user/file.txt", in: ctx))
    }

    @Test("fsScope is decoded when present and used for path checks")
    func fsScopeDecodedWhenPresent() throws {
        let json = #"""
            {
            "fsScope": {
            "allow": ["$HOME/Documents/**"],
            "deny": ["$HOME/Documents/secret/**"]
            }
            }
            """#
        let scope = try JSONDecoder().decode(KSShellScope.self, from: Data(json.utf8))
        let ctx = KSFSScope.ExpansionContext(
            app: "/app", home: "/home/user", docs: "/home/user/Documents", temp: "/tmp")
        #expect(scope.fsScope.permits(absolutePath: "/home/user/Documents/file.txt", in: ctx))
        #expect(!scope.fsScope.permits(absolutePath: "/home/user/Documents/secret/key", in: ctx))
        #expect(!scope.fsScope.permits(absolutePath: "/etc/passwd", in: ctx))
    }
}
