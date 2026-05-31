import Testing

@testable import Kalsae

@Suite("KSApp.resolveInjectedCSP")
struct KSAppResolveInjectedCSPTests {
    @Test("injectCSP=false returns nil in production mode")
    func injectDisabledInProdReturnsNil() {
        let security = KSSecurityConfig(
            injectCSP: false,
            csp: "default-src 'self'",
            devCsp: "default-src 'self' http://localhost:*")
        let resolved = KSApp.resolveInjectedCSP(security: security, isDev: false)
        #expect(resolved == nil)
    }

    @Test("injectCSP=false returns nil in dev mode")
    func injectDisabledInDevReturnsNil() {
        let security = KSSecurityConfig(
            injectCSP: false,
            csp: "default-src 'self'",
            devCsp: "default-src 'self' http://localhost:*")
        let resolved = KSApp.resolveInjectedCSP(security: security, isDev: true)
        #expect(resolved == nil)
    }

    @Test("injectCSP=true uses csp in production mode")
    func injectEnabledInProdUsesCSP() {
        let security = KSSecurityConfig(
            injectCSP: true,
            csp: "default-src 'self' https://example.com")
        let resolved = KSApp.resolveInjectedCSP(security: security, isDev: false)
        #expect(resolved == "default-src 'self' https://example.com")
    }

    @Test("injectCSP=true uses devCsp in dev mode with csp fallback")
    func injectEnabledInDevUsesDevCSPOrFallback() {
        let withDev = KSSecurityConfig(
            injectCSP: true,
            csp: "default-src 'self'",
            devCsp: "default-src 'self' http://localhost:*")
        let withoutDev = KSSecurityConfig(
            injectCSP: true,
            csp: "default-src 'self'")

        let devResolved = KSApp.resolveInjectedCSP(security: withDev, isDev: true)
        let fallbackResolved = KSApp.resolveInjectedCSP(security: withoutDev, isDev: true)

        #expect(devResolved == "default-src 'self' http://localhost:*")
        #expect(fallbackResolved == "default-src 'self'")
    }
}
