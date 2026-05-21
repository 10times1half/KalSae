#if os(Windows)
    internal import WinSDK
    internal import CKalsaeWV2
    public import KalsaeCore
    import Foundation

    // MARK: - KSWindowsWindowBackend + 작업 표시줄 (Taskbar) 통합

    // 이 확장은 `ITaskbarList3` COM 인터페이스를 통해 작업 표시줄 버튼에
    // 진행률 표시, 오버레이 아이콘을 설정하고, 윈도우 드래그 시작을
    // 지원한다. 모든 호출은 C++ shim (`CKalsaeWV2`)의
    // `KSWV2_SetTaskbarProgress` / `KSWV2_SetOverlayIcon` 함수를 통해
    // 이루어진다.

    extension KSWindowsWindowBackend {

        // MARK: setTaskbarProgress — 작업 표시줄 진행률 표시

        /// 작업 표시줄 버튼에 진행률 표시줄을 설정한다.
        ///
        /// 내부적으로 `ITaskbarList3::SetProgressState`와
        /// `SetProgressValue`를 호출한다. C++ shim 함수
        /// `KSWV2_SetTaskbarProgress(hwnd, state, value)`는 이 두 호출을
        /// 한 번에 수행한다.
        ///
        /// `KSTaskbarProgress` enum의 각 케이스는 `KSWV2_TaskbarState`에
        /// 대응한다:
        /// - `.none` → TBPF_NOPROGRESS (0) — 진행률 숨김
        /// - `.indeterminate` → TBPF_INDETERMINATE (1) — 무한 진행(애니메이션)
        /// - `.normal(v)` → TBPF_NORMAL (2) — 일반 진행 (0~100)
        /// - `.error(v)` → TBPF_ERROR (3) — 오류 진행 (빨간색)
        /// - `.paused(v)` → TBPF_PAUSED (4) — 일시 정지 (노란색)
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

        // MARK: setOverlayIcon — 작업 표시줄 오버레이 아이콘

        /// 작업 표시줄 버튼의 오른쪽 아래에 오버레이 아이콘을 표시한다.
        ///
        /// `ITaskbarList3::SetOverlayIcon`을 통해 설정한다.
        /// `iconPath`가 nil이면 현재 오버레이를 제거한다.
        ///
        /// - Parameters:
        ///   - handle: 대상 윈도우 핸들
        ///   - iconPath: 오버레이에 표시할 `.ico` 파일의 전체 경로
        ///   - description: 접근성 설명 (AT에 전달)
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
                    // iconPath가 nil이면 오버레이 제거
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

        // MARK: startDrag — 윈도우 드래그 시작 (RFC-005 §4.6)

        /// 제목 표시줄이 없는 윈도우에서 마우스 드래그로 윈도우를
        /// 이동할 수 있도록 WM_NCLBUTTONDOWN 메시지를 시뮬레이션한다.
        ///
        /// `SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, MAKELPARAM(x, y))`
        /// 를 전송하여 Win32가 캡션 이동 동작을 수행하게 한다.
        /// (RFC-005 §4.6 참고)
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

        // MARK: - HWND resolution 헬퍼

        // Win32 HWND 조회는 `@MainActor` 격리된 `KSWin32HandleRegistry`/
        // `Win32App.shared` 접근이 필요하다. 하지만 `setTaskbarProgress`
        // 와 `setOverlayIcon`의 나머지 호출은 `withCString` 같은 stdlib
        // 제네릭 클로저에 문자열을 전달한다. `@MainActor` 격리 상태에서
        // stdlib 제네릭을 호출하면 Win32 UI 스레드에서
        // `dispatch_assert_queue` 트랩이 발생할 수 있다.
        //
        // 이 헬퍼를 `nonisolated`로 선언하고, 좁은 범위의
        // `runOnUIThreadIsolated` 블록에서만 HWND를 조회함으로써
        // `@MainActor` 격리 전파를 차단한다.
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

        // MARK: - 내부 헬퍼

        /// `KSTaskbarProgress` enum을 C shim이 이해하는
        /// `KSWV2_TaskbarState`(Int32) + value(UInt32, 0~100)로 변환한다.
        ///
        /// `KSTaskbarProgress`의 value는 0.0~1.0 Double이므로 100을
        /// 곱한 후 0~100 범위로 clamp한다.
        private func taskbarStateAndValue(from progress: KSTaskbarProgress) -> (Int32, UInt32) {
            switch progress {
            case .none:
                return (0, 0)  // TBPF_NOPROGRESS
            case .indeterminate:
                return (1, 0)  // TBPF_INDETERMINATE
            case .normal(let v):
                return (2, UInt32((v * 100).clamped(to: 0...100)))  // TBPF_NORMAL
            case .error(let v):
                return (3, UInt32((v * 100).clamped(to: 0...100)))  // TBPF_ERROR
            case .paused(let v):
                return (4, UInt32((v * 100).clamped(to: 0...100)))  // TBPF_PAUSED
            }
        }
    }

    // MARK: - Double clamping 헬퍼

    extension Double {
        /// 값을 주어진 범위로 제한한다 (clamp).
        fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
            Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
        }
    }
#endif
