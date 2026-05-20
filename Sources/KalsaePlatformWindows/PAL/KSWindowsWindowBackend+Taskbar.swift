#if os(Windows)
    internal import WinSDK
    internal import CKalsaeWV2
    public import KalsaeCore
    import Foundation

    // MARK: - KSWindowsWindowBackend + Taskbar integration

    extension KSWindowsWindowBackend {

        // MARK: setTaskbarProgress

        public func setTaskbarProgress(
            _ handle: KSWindowHandle, progress: KSTaskbarProgress
        ) async throws(KSError) {
            let hwnd: HWND = try Self._resolveHWNDForCall(handle, label: "setTaskbarProgress")
            let (state, value) = taskbarStateAndValue(from: progress)
            let result: Result<Void, KSError> = Win32App.runOnUIThread {
                let hr = KSWV2_SetTaskbarProgress(hwnd, state, value)
                if hr < 0 {
                    return .failure(
                        KSError(
                            code: .unsupportedPlatform,
                            message:
                                "ITaskbarList3.SetProgressState/Value failed: 0x\(String(UInt32(bitPattern: hr), radix: 16, uppercase: true))"
                        ))
                }
                return .success(())
            }
            try result.unwrap()
        }

        // MARK: setOverlayIcon

        public func setOverlayIcon(
            _ handle: KSWindowHandle, iconPath: String?, description: String?
        ) async throws(KSError) {
            let hwnd: HWND = try Self._resolveHWNDForCall(handle, label: "setOverlayIcon")
            let result: Result<Void, KSError> = Win32App.runOnUIThread {
                let hr: Int32
                if let path = iconPath {
                    hr = path.withCString(encodedAs: UTF16.self) { pathPtr in
                        if let desc = description {
                            return desc.withCString(encodedAs: UTF16.self) { descPtr in
                                KSWV2_SetOverlayIcon(hwnd, pathPtr, descPtr)
                            }
                        } else {
                            return KSWV2_SetOverlayIcon(hwnd, pathPtr, nil)
                        }
                    }
                } else {
                    hr = KSWV2_SetOverlayIcon(hwnd, nil, nil)
                }
                if hr < 0 {
                    return .failure(
                        KSError(
                            code: .unsupportedPlatform,
                            message:
                                "ITaskbarList3.SetOverlayIcon failed: 0x\(String(UInt32(bitPattern: hr), radix: 16, uppercase: true))"
                        ))
                }
                return .success(())
            }
            try result.unwrap()
        }

        // MARK: startDrag (RFC-005 §4.6)

        public func startDrag(_ handle: KSWindowHandle) async throws(KSError) {
            let result: Result<Void, KSError> = Win32App.runOnUIThreadIsolated {
                do {
                    let win = try self.windowSync(for: handle)
                    win.startDrag()
                    return .success(())
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            try result.unwrap()
        }

        // MARK: - HWND resolution helper
        //
        // The Win32 HWND lookup needs `@MainActor` access to
        // `KSWin32HandleRegistry` / `Win32App.shared`, but the rest of these
        // calls feed strings into stdlib generic closures (`withCString`).
        // Resolving the HWND here in a narrow `runOnUIThreadIsolated` block
        // keeps the outer dispatch nonisolated so the
        // `@MainActor`-closure trap (dispatch_assert_queue) cannot fire.
        nonisolated internal static func _resolveHWNDForCall(
            _ handle: KSWindowHandle, label op: String
        ) throws(KSError) -> HWND {
            let result: Result<HWND, KSError> = Win32App.runOnUIThreadIsolated {
                guard let hwnd = KSWin32HandleRegistry.shared.hwnd(for: handle) else {
                    return .failure(
                        KSError(
                            code: .windowCreationFailed,
                            message: "\(op): no window registered for '\(handle.label)'"))
                }
                return .success(hwnd)
            }
            return try result.unwrap()
        }

        // MARK: - Private helpers

        /// `KSTaskbarProgress`를 `KSWV2_TaskbarState` + value (0–100)로 변환한다.
        private func taskbarStateAndValue(from progress: KSTaskbarProgress) -> (Int32, UInt32) {
            switch progress {
            case .none:
                return (0, 0)
            case .indeterminate:
                return (1, 0)
            case .normal(let v):
                return (2, UInt32((v * 100).clamped(to: 0...100)))
            case .error(let v):
                return (3, UInt32((v * 100).clamped(to: 0...100)))
            case .paused(let v):
                return (4, UInt32((v * 100).clamped(to: 0...100)))
            }
        }
    }

    // MARK: - Double clamping helper

    extension Double {
        fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
            Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
        }
    }
#endif
