#if os(Android)
    import Testing
    import Foundation
    @testable import KalsaePlatformAndroid
    import KalsaeCore

    // MARK: - KSAndroidPermissions

    @Suite("KSAndroidPermissions — state registry")
    struct KSAndroidPermissionsTests {

        @Test("default state is notDetermined")
        func defaultState() {
            let perms = KSAndroidPermissions()
            #expect(perms.state(for: "POST_NOTIFICATIONS") == .notDetermined)
        }

        @Test("setState / state round-trip")
        func roundTrip() {
            let perms = KSAndroidPermissions()
            perms.setState(.granted, for: "POST_NOTIFICATIONS")
            #expect(perms.state(for: "POST_NOTIFICATIONS") == .granted)
            #expect(perms.isGranted("POST_NOTIFICATIONS") == true)
        }

        @Test("isGranted returns false when denied")
        func isGrantedFalseWhenDenied() {
            let perms = KSAndroidPermissions()
            perms.setState(.denied, for: "POST_NOTIFICATIONS")
            #expect(perms.isGranted("POST_NOTIFICATIONS") == false)
        }
    }
#endif
