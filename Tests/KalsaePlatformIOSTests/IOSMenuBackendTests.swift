#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSMenuBackend 계약 (Phase iOS-Stable §1.2:
    // installAppMenu/installWindowMenu = no-op + warn-once;
    // showContextMenu = UIAlertController + KSiOSCommandRouter)

    @Suite("KSiOSMenuBackend — no-op install + actionSheet context menu")
    struct KSiOSMenuBackendTests {

        @Test("installAppMenu is a no-op (does not throw)")
        func installAppMenuNoOp() async throws {
            let backend = KSiOSMenuBackend()
            try await backend.installAppMenu([])
            // 두 번째 호출도 no-op (warn-once 가드).
            try await backend.installAppMenu([
                .action(id: "x", label: "X", command: "ks.test")
            ])
        }

        @Test("installWindowMenu is a no-op (does not throw)")
        func installWindowMenuNoOp() async throws {
            let backend = KSiOSMenuBackend()
            let handle = KSWindowHandle(label: "ks-test-ios-menu", rawValue: 1)
            try await backend.installWindowMenu(handle, items: [])
        }

        @Test("showContextMenu silently no-ops when no parent VC is available")
        func showContextMenuNoParent() async throws {
            let backend = KSiOSMenuBackend()
            let handle = KSWindowHandle(label: "ks-test-ios-menu-ctx", rawValue: 99)
            // Registry 에 등록된 윈도우가 없어 parentVC = nil → silent drop (Android 와 동일).
            try await backend.showContextMenu(
                [.action(id: "a", label: "A", command: "ks.test.a")],
                at: KSPoint(x: 10, y: 20),
                in: handle)
        }

        @Test("showContextMenu with empty action list is a no-op")
        func showContextMenuEmpty() async throws {
            let backend = KSiOSMenuBackend()
            try await backend.showContextMenu([], at: KSPoint(x: 0, y: 0), in: nil)
        }
    }

    @Suite("KSiOSCommandRouter — pub/sub fanout")
    @MainActor
    struct KSiOSCommandRouterTests {

        @Test("subscribe + dispatch round-trip")
        func subscribeFanout() {
            let router = KSiOSCommandRouter.shared
            router.clear()
            var calls: [(String, String?)] = []
            router.subscribe { cmd, id in calls.append((cmd, id)) }
            // dispatch 는 internal 이라 @testable import KalsaePlatformIOS 로 노출됨.
            router.dispatch(command: "ks.test", itemID: "x")
            #expect(calls.count == 1)
            #expect(calls.first?.0 == "ks.test")
            #expect(calls.first?.1 == "x")
            router.clear()
        }
    }
#endif
