#if os(Linux)
    import Testing
    import Foundation
    @testable import KalsaePlatformLinux
    import KalsaeCore

    @Suite("KSLinuxNotificationBackend — integration contract")
    struct KSLinuxNotificationIntegrationTests {

        @Test("requestPermission always returns true")
        func requestPermissionAlwaysTrue() async {
            let backend = KSLinuxNotificationBackend()
            let first = await backend.requestPermission()
            let second = await backend.requestPermission()
            #expect(first)
            #expect(second)
        }

        @Test("cancel is no-op and does not throw")
        func cancelIsNoop() async {
            let backend = KSLinuxNotificationBackend()
            await backend.cancel(id: "ks-notification-\(UUID().uuidString)")
        }

        @Test("post either succeeds or throws io")
        func postErrorMapping() async {
            let backend = KSLinuxNotificationBackend()
            let notification = KSNotification(
                id: "ks-noti-\(UUID().uuidString)",
                title: "Kalsae Linux Notification Contract",
                body: "integration-test"
            )

            do {
                try await backend.post(notification)
                // 환경 의존: notify-send이 있고 작동 중일 때 성공한다.
            } catch let error {
                #expect(
                    error.code == .io,
                    "Expected io on failure, got \(error.code)")
            }
        }
    }
#endif
