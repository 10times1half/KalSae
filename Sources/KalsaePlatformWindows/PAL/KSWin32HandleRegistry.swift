#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore
    internal import Foundation

    /// Resolves a `KSWindowHandle` to a Win32 `HWND`.
    ///
    /// Used by every PAL backend (dialogs, menus, tray) to find the parent
    /// window that anchors a modal call. Maps window label → HWND for all
    /// live windows.
    @MainActor
    internal final class KSWin32HandleRegistry {
        static let shared = KSWin32HandleRegistry()

        private var byLabel: [String: HWND] = [:]
        private init() {}

        func register(label: String, hwnd: HWND) {
            byLabel[label] = hwnd
        }

        func unregister(label: String) {
            byLabel.removeValue(forKey: label)
        }

        func hwnd(for handle: KSWindowHandle) -> HWND? {
            if let h = byLabel[handle.label] { return h }
            // rawValue 비트 패턴으로 폴백.
            return HWND(bitPattern: UInt(handle.rawValue))
        }

        func handle(for label: String) -> KSWindowHandle? {
            guard let hwnd = byLabel[label] else { return nil }
            return KSWindowHandle(
                label: label,
                rawValue: UInt64(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd)))))
        }
    }

    /// Box that lets us return non-Sendable Win32 results across an `await`
    /// hop into MainActor. We never touch the box from a thread other than
    /// the one that produced it, so `@unchecked Sendable` is safe.
    internal final class KSSendableBox<Value>: @unchecked Sendable {
        let value: Value
        init(_ v: Value) { self.value = v }
    }

    extension Result where Failure == KSError {
        /// Typed-throws unwrap. `Result.get()` rethrows untyped, which loses
        /// the `throws(KSError)` contract of our PAL functions; this helper
        /// preserves it.
        @inline(__always)
        func unwrap() throws(KSError) -> Success {
            switch self {
            case .success(let v): return v
            case .failure(let e): throw e
            }
        }
    }
#endif
