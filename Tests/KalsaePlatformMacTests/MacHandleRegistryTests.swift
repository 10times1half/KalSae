#if os(macOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformMac
    import KalsaeCore

    // MARK: - KSMacHandleRegistry 직접 검증
    //
    // `KSMacHandleRegistry`는 레이블/rawValue 양방향 조회를 지원한다.
    // `@testable import` 로 internal 타입에 접근한다.

    @Suite("KSMacHandleRegistry — direct registry contract", .serialized)
    @MainActor
    struct KSMacHandleRegistryTests {

        private func makeWindow() throws -> KSMacWindow {
            KSMacApp.shared.ensureInitialized()
            return try KSMacWindow(
                config: KSWindowConfig(
                    label: "ks-test-mac-reg-\(UUID().uuidString.prefix(8).lowercased())",
                    title: "KS Registry Test",
                    width: 320,
                    height: 240,
                    visible: false
                ))
        }

        /// `register` 후 `handle(for:)`이 레이블과 rawValue를 정확히 반환해야 한다.
        @Test("register then handle(for:) returns matching handle")
        func registerThenFind() throws {
            let window = try makeWindow()
            let label = window.config.label
            let raw = UInt64(UInt(bitPattern: ObjectIdentifier(window)))
            KSMacHandleRegistry.shared.register(label: label, rawValue: raw, window: window)
            defer { KSMacHandleRegistry.shared.unregister(label: label) }

            let handle = KSMacHandleRegistry.shared.handle(for: label)
            #expect(handle != nil)
            #expect(handle?.label == label)
        }

        /// `unregister` 후 `allWindows()`에서 제거돼야 한다.
        @Test("unregister removes window from allWindows()")
        func unregisterRemovesFromAllWindows() throws {
            let window = try makeWindow()
            let label = window.config.label
            let raw = UInt64(UInt(bitPattern: ObjectIdentifier(window)))
            KSMacHandleRegistry.shared.register(label: label, rawValue: raw, window: window)

            KSMacHandleRegistry.shared.unregister(label: label)
            let all = KSMacHandleRegistry.shared.allWindows()
            #expect(!all.contains { $0 === window })
        }

        /// `unregister` 후 `window(for:)`이 `nil`을 반환해야 한다.
        @Test("window(for:) returns nil after unregister")
        func windowForNilAfterUnregister() throws {
            let window = try makeWindow()
            let label = window.config.label
            let raw = UInt64(UInt(bitPattern: ObjectIdentifier(window)))
            let handle = KSWindowHandle(label: label, rawValue: raw)
            KSMacHandleRegistry.shared.register(label: label, rawValue: raw, window: window)

            KSMacHandleRegistry.shared.unregister(label: label)
            let found = KSMacHandleRegistry.shared.window(for: handle)
            #expect(found == nil)
        }
    }
#endif
