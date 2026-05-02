import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSNotificationScope")
struct KSNotificationScopeTests {
    @Test("Defaults permit all three operations")
    func defaultsPermitAll() {
        let scope = KSNotificationScope()
        #expect(scope.post)
        #expect(scope.cancel)
        #expect(scope.requestPermission)
    }

    @Test("Decodes from JSON with explicit denials")
    func decodesDenials() throws {
        let json = #"{"post": false, "cancel": false, "requestPermission": false}"#
        let scope = try JSONDecoder().decode(KSNotificationScope.self, from: Data(json.utf8))
        #expect(!scope.post)
        #expect(!scope.cancel)
        #expect(!scope.requestPermission)
    }

    @Test("Missing keys fall back to safe defaults")
    func missingKeysUseDefaults() throws {
        let scope = try JSONDecoder().decode(KSNotificationScope.self, from: Data("{}".utf8))
        #expect(scope.post)
        #expect(scope.cancel)
        #expect(scope.requestPermission)
    }

    @Test("Embedded notifications field round-trips inside KSSecurityConfig")
    func roundTripsInsideSecurity() throws {
        let json = #"""
            {
            "csp": "default-src 'self'",
            "notifications": {
            "post": true,
            "cancel": false,
            "requestPermission": true
            }
            }
            """#
        let sec = try JSONDecoder().decode(KSSecurityConfig.self, from: Data(json.utf8))
        #expect(sec.notifications.post)
        #expect(!sec.notifications.cancel)
        #expect(sec.notifications.requestPermission)
    }

    @Test("Missing notifications key on security config falls back to defaults")
    func missingNotificationsKey() throws {
        let json = #"{"csp": "x"}"#
        let sec = try JSONDecoder().decode(KSSecurityConfig.self, from: Data(json.utf8))
        #expect(sec.notifications.post)
        #expect(sec.notifications.cancel)
        #expect(sec.notifications.requestPermission)
    }
}
