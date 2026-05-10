#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSAutostartBackend 계약 (stub — all throw)

    @Suite("KSiOSAutostartBackend — stub throws unsupportedPlatform")
    struct KSiOSAutostartBackendTests {

        let backend = KSiOSAutostartBackend()

        @Test("isEnabled returns false")
        func isEnabledReturnsFalse() {
            #expect(!backend.isEnabled())
        }

        @Test("enable throws unsupportedPlatform")
        func enableThrows() {
            do {
                try backend.enable()
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("disable throws unsupportedPlatform")
        func disableThrows() {
            do {
                try backend.disable()
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }
    }
#endif
