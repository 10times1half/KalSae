#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore

    /// `PostMessageW`를 통해 클로저를 윈도우의 UI 스레드로 포스트한다.
    /// 인스턴스 격리 없이 어느 스레드에서든 호출 가능한 자유 함수다.
    /// `PostMessageW`는 문서상 스레드 안전이 보장된다.
    internal func ksPostUIJob(hwnd: HWND, block: @escaping @MainActor () -> Void) {
        let box = _KBUIJobPlainBox(block: block)
        let raw = Unmanaged.passRetained(box).toOpaque()
        let wp = WPARAM(UInt(bitPattern: Int(bitPattern: raw)))
        _ = PostMessageW(hwnd, UINT(WM_USER) + 1, wp, 0)
    }

    /// UI 작업 retain 용 박스. `@unchecked Sendable` — 유일한 가변 상태인
    /// 클로저는 UI 스레드에서만 실행되고 한 번 호출 후 폐기된다.
    internal final class _KBUIJobPlainBox: @unchecked Sendable {
        let block: @MainActor () -> Void
        init(block: @escaping @MainActor () -> Void) { self.block = block }
    }
#endif
