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
            let result: Result<Void, KSError> = await MainActor.run {
                do {
                    let win = try windowSync(for: handle)
                    guard let hwnd = win.hwnd else {
                        throw KSError(
                            code: .windowCreationFailed,
                            message: "setTaskbarProgress: window '\(handle.label)' has no HWND")
                    }
                    let (state, value) = taskbarStateAndValue(from: progress)
                    let hr = KSWV2_SetTaskbarProgress(hwnd, state, value)
                    if hr < 0 {
                        throw KSError(
                            code: .unsupportedPlatform,
                            message:
                                "ITaskbarList3.SetProgressState/Value failed: 0x\(String(UInt32(bitPattern: hr), radix: 16, uppercase: true))"
                        )
                    }
                    return .success(())
                } catch let e as KSError {
                    return .failure(e)
                } catch {
                    return .failure(KSError(code: .internal, message: "\(error)"))
                }
            }
            if case .failure(let e) = result { throw e }
        }

        // MARK: setOverlayIcon

        public func setOverlayIcon(
            _ handle: KSWindowHandle, iconPath: String?, description: String?
        ) async throws(KSError) {
            let result: Result<Void, KSError> = await MainActor.run {
                do {
                    let win = try windowSync(for: handle)
                    guard let hwnd = win.hwnd else {
                        throw KSError(
                            code: .windowCreationFailed,
                            message: "setOverlayIcon: window '\(handle.label)' has no HWND")
                    }
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
                        throw KSError(
                            code: .unsupportedPlatform,
                            message:
                                "ITaskbarList3.SetOverlayIcon failed: 0x\(String(UInt32(bitPattern: hr), radix: 16, uppercase: true))"
                        )
                    }
                    return .success(())
                } catch let e as KSError {
                    return .failure(e)
                } catch {
                    return .failure(KSError(code: .internal, message: "\(error)"))
                }
            }
            if case .failure(let e) = result { throw e }
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
