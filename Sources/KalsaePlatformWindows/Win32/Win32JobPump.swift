#if os(Windows)
internal import WinSDK
public import KalsaeCore

/// Posts a closure onto a window's UI thread via `PostMessageW`. Free
/// function (not instance-isolated) because it must be callable from any
/// thread. `PostMessageW` is documented thread-safe.
internal func ksPostUIJob(hwnd: HWND, block: @escaping @MainActor () -> Void) {
    let box = _KBUIJobPlainBox(block: block)
    let raw = Unmanaged.passRetained(box).toOpaque()
    let wp = WPARAM(UInt(bitPattern: Int(bitPattern: raw)))
    _ = PostMessageW(hwnd, UINT(WM_USER) + 1, wp, 0)
}

/// Retain-vehicle class for UI jobs. `@unchecked Sendable` because its
/// only mutable state — the closure — runs on the UI thread and is
/// discarded after one call.
internal final class _KBUIJobPlainBox: @unchecked Sendable {
    let block: @MainActor () -> Void
    init(block: @escaping @MainActor () -> Void) { self.block = block }
}
#endif
