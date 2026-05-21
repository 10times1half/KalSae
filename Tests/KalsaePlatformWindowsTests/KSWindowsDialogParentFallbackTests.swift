#if os(Windows)
    import Testing
    import Foundation
    @testable import KalsaePlatformWindows
    import KalsaeCore

    /// Bug 1 회귀 — 다이얼로그 부모 HWND 폴백 정책 단위 테스트.
    ///
    /// 운영 코드의 `_resolveDialogParent(...)` 는 4단계 폴백을 수행한다:
    /// 1. handle → registry hit → 사용
    /// 2. nil → `GetActiveWindow()`
    /// 3. nil → `GetForegroundWindow()`
    /// 4. nil → 결과 nil (다이얼로그가 톱레벨로 표시)
    /// 폴백이 성공하면 `SetForegroundWindow(hwnd)` 호출 — z-order 보정.
    ///
    /// 본 테스트는 WinAPI 호출을 closure 로 주입하여 순수 로직만 검증한다.
    @Suite("KSWindowsDialogBackend — parent fallback policy")
    struct KSWindowsDialogParentFallbackTests {

        // Fake 'HWND' 포인터 — 실제 윈도우와 무관, 순수 값 비교용.
        // `nonisolated(unsafe)`: `UnsafeMutableRawPointer` 는 Sendable 아님 —
        // 테스트 컨텍스트에서만 비교 값으로 쓰이고 dereference 하지 않으므로 안전.
        private nonisolated(unsafe) static let regHWND = UnsafeMutableRawPointer(
            bitPattern: 0x1001)!
        private nonisolated(unsafe) static let activeHWND = UnsafeMutableRawPointer(
            bitPattern: 0x2002)!
        private nonisolated(unsafe) static let foregroundHWND = UnsafeMutableRawPointer(
            bitPattern: 0x3003)!

        private static let demoHandle = KSWindowHandle(
            label: "main", rawValue: 1)

        /// 1단계 적중: registry 가 HWND 를 반환하면 다른 폴백은 호출되지 않는다.
        @Test("Registry hit short-circuits remaining fallbacks")
        func registryHit() {
            var setForegroundCallCount = 0
            var setForegroundArg: UnsafeMutableRawPointer? = nil
            let result = KSWindowsDialogBackend._resolveDialogParent(
                handle: Self.demoHandle,
                registryLookup: { _ in Self.regHWND },
                activeWindow: {
                    Issue.record("activeWindow should not be called on registry hit")
                    return nil
                },
                foregroundWindow: {
                    Issue.record("foregroundWindow should not be called on registry hit")
                    return nil
                },
                setForeground: { ptr in
                    setForegroundCallCount += 1
                    setForegroundArg = ptr
                })
            #expect(result == Self.regHWND)
            #expect(setForegroundCallCount == 1)
            #expect(setForegroundArg == Self.regHWND)
        }

        /// 2단계: handle 이 nil 이면 `GetActiveWindow()` 로 폴백.
        @Test("Nil handle falls back to GetActiveWindow")
        func nilHandleActiveFallback() {
            var setForegroundArg: UnsafeMutableRawPointer? = nil
            let result = KSWindowsDialogBackend._resolveDialogParent(
                handle: nil,
                registryLookup: { _ in
                    Issue.record("registryLookup should not be called on nil handle")
                    return nil
                },
                activeWindow: { Self.activeHWND },
                foregroundWindow: {
                    Issue.record("foregroundWindow should not be called after active hit")
                    return nil
                },
                setForeground: { setForegroundArg = $0 })
            #expect(result == Self.activeHWND)
            #expect(setForegroundArg == Self.activeHWND)
        }

        /// 3단계: registry 미스 + active 미스 → `GetForegroundWindow()` 폴백.
        @Test("Registry miss + active miss → GetForegroundWindow")
        func foregroundFallback() {
            var setForegroundArg: UnsafeMutableRawPointer? = nil
            let result = KSWindowsDialogBackend._resolveDialogParent(
                handle: Self.demoHandle,
                registryLookup: { _ in nil },
                activeWindow: { nil },
                foregroundWindow: { Self.foregroundHWND },
                setForeground: { setForegroundArg = $0 })
            #expect(result == Self.foregroundHWND)
            #expect(setForegroundArg == Self.foregroundHWND)
        }

        /// 4단계: 모든 폴백 미스 → nil. `setForeground` 호출되지 않는다.
        @Test("All misses → nil, no setForeground side-effect")
        func allMisses() {
            var setForegroundCallCount = 0
            let result = KSWindowsDialogBackend._resolveDialogParent(
                handle: Self.demoHandle,
                registryLookup: { _ in nil },
                activeWindow: { nil },
                foregroundWindow: { nil },
                setForeground: { _ in setForegroundCallCount += 1 })
            #expect(result == nil)
            #expect(setForegroundCallCount == 0)
        }
    }
#endif
