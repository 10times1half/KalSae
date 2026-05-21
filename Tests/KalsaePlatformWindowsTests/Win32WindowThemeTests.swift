#if os(Windows)
    import Testing
    import Foundation
    import WinSDK
    @testable import KalsaePlatformWindows

    /// Bug 2 회귀 — `Win32Window._applyImmersiveDarkMode` 의 격리/시그니처
    /// 보호 테스트.
    ///
    /// 원래 버그: `setTheme(.light)` 호출 시 `withUnsafePointer` (stdlib
    /// generic 클로저) 가 `@MainActor` 컨텍스트에서 실행되어 Win32 UI
    /// 스레드에서 `dispatch_assert_queue` 트랩으로 `STATUS_ILLEGAL_INSTRUCTION`
    /// 발생. 수정: DWM 호출을 `nonisolated static` 헬퍼로 분리.
    ///
    /// 본 테스트는 헬퍼의 타입 시그니처가 `nonisolated` (즉 `@Sendable` 값
    /// 으로 캡처 가능) 임을 컴파일타임에 단언한다. 누군가 `nonisolated` 를
    /// 제거하거나 `@MainActor` 로 표시하면 본 파일이 컴파일에 실패한다.
    @Suite("Win32Window — _applyImmersiveDarkMode isolation")
    struct Win32WindowThemeTests {

        /// 헬퍼가 `@Sendable (HWND, Bool) -> Void` 함수값으로 캡처 가능해야
        /// 한다. 액터 격리가 추가되면 이 캡처가 컴파일 거부된다.
        @Test("_applyImmersiveDarkMode captures as @Sendable function value")
        func helperIsNonisolated() {
            let f: @Sendable (HWND, Bool) -> Void =
                Win32Window._applyImmersiveDarkMode(hwnd:dark:)
            _ = f  // 캡처 자체가 회귀 단언 — 호출은 실제 HWND 가 필요하므로 생략.
        }
    }
#endif
