import Foundation

import Testing

@testable import KalsaeCore

@Suite("KSSecurityConfig.injectCSP")
struct KSSecurityConfigInjectCSPTests {
    @Test("Missing injectCSP key defaults to true")
    func missingKeyDefaultsTrue() throws {
        let json = #"{"csp":"default-src 'self'"}"#
        let sec = try JSONDecoder().decode(KSSecurityConfig.self, from: Data(json.utf8))
        #expect(sec.injectCSP)
    }

    @Test("Explicit false is decoded")
    func explicitFalseIsDecoded() throws {
        let json = #"{"injectCSP":false,"csp":"default-src 'self'"}"#
        let sec = try JSONDecoder().decode(KSSecurityConfig.self, from: Data(json.utf8))
        #expect(!sec.injectCSP)
    }
}
