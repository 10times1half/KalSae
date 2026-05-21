#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    import Foundation

    // MARK: - KSWindowsWindowBackend + 디스플레이 (Display) 열거 / 조회

    // 이 확장은 연결된 모니터의 정보(`KSDisplayInfo`)를 열거하고
    // (`listDisplays()`), 특정 윈도우가 위치한 모니터를 조회한다
    // (`currentDisplay(_:)`).
    //
    // 모든 정보는 Win32의 `EnumDisplayMonitors` / `MonitorFromWindow` /
    // `GetMonitorInfoW` / `GetDpiForMonitor` / `EnumDisplaySettingsW`
    // API를 통해 수집한다.

    extension KSWindowsWindowBackend {

        // MARK: listDisplays — 모든 모니터 정보 열거

        /// 연결된 모든 모니터의 `KSDisplayInfo` 배열을 반환한다.
        ///
        /// 내부 처리 순서:
        /// 1. `EnumDisplayMonitors`로 모든 모니터 열거 (콜백 방식)
        /// 2. 각 모니터에 대해:
        ///    - `GetMonitorInfoW` → `MONITORINFOEXW` → bounds(`rcMonitor`),
        ///      workArea(`rcWork`), primary 여부(`MONITORINFOF_PRIMARY`)
        ///    - `GetDpiForMonitor(MDT_EFFECTIVE_DPI)` → scaleFactor (dpi / 96.0)
        ///    - `EnumDisplaySettingsW(ENUM_CURRENT_SETTINGS)` → `DEVMODEW`
        ///      → refreshRate (`dmDisplayFrequency`)
        ///    - 모니터 핸들의 포인터 값을 16자리 16진수 문자열로 고유 ID 생성
        /// 3. 모니터가 하나도 없으면 `unsupportedPlatform` 에러 반환
        ///
        /// 콜백 컨텍스트 전달에는 `Unmanaged.passUnretained`를 사용한다
        /// (콜백이 동기적으로 완료되므로 retain/unretained가 안전).
        public func listDisplays() async throws(KSError) -> [KSDisplayInfo] {
            let result: Result<[KSDisplayInfo], KSError> = Win32App.runOnUIThread {
                // `EnumDisplayMonitors` Win32 콜백에서 결과를 누적할 박스.
                // 콜백은 동기적으로 완료되므로 `Unmanaged.passUnretained`로
                // 전달해도 안전하다.
                final class DisplayBox { var displays: [KSDisplayInfo] = [] }
                let box = DisplayBox()
                let lpParam = LPARAM(Int(bitPattern: Unmanaged.passUnretained(box).toOpaque()))
                EnumDisplayMonitors(
                    nil,  // HDC (전체 가상 화면)
                    nil,  // clipping rect (전체 화면)
                    { hMon, _, _, lpParam -> WindowsBool in
                        guard
                            let rawPtr = UnsafeMutableRawPointer(
                                bitPattern: UInt(bitPattern: Int(lpParam))),
                            let hMon
                        else { return WindowsBool(true) }  // 다음 모니터 계속
                        let box = Unmanaged<DisplayBox>.fromOpaque(rawPtr).takeUnretainedValue()

                        // ── MONITORINFOEXW ──────────────────────
                        var info = MONITORINFOEXW()
                        info.cbSize = DWORD(MemoryLayout<MONITORINFOEXW>.size)
                        let ok: Bool = withUnsafeMutablePointer(to: &info) { p in
                            p.withMemoryRebound(to: MONITORINFO.self, capacity: 1) {
                                Bool(GetMonitorInfoW(hMon, $0))
                            }
                        }
                        guard ok else { return WindowsBool(true) }

                        // ── DPI / scale factor ──────────────────
                        var dpiX: UINT = 96
                        var dpiY: UINT = 96
                        _ = GetDpiForMonitor(hMon, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)
                        let scale = Double(dpiX) / 96.0

                        // ── 장치 이름 (szDevice) ────────────────
                        let deviceName: String = withUnsafeBytes(of: info.szDevice) { raw in
                            guard let base = raw.bindMemory(to: WCHAR.self).baseAddress
                            else { return "" }
                            return String(decodingCString: base, as: UTF16.self)
                        }

                        // ── 주사율 (refresh rate) ───────────────
                        // `EnumDisplaySettingsW(ENUM_CURRENT_SETTINGS)`로
                        // 현재 설정의 DEVMODE를 가져와 `dmDisplayFrequency`를 읽는다.
                        var devMode = DEVMODEW()
                        devMode.dmSize = WORD(MemoryLayout<DEVMODEW>.size)
                        var refreshRate: Int? = nil
                        if Bool(
                            deviceName.withCString(encodedAs: UTF16.self) {
                                EnumDisplaySettingsW($0, 0xFFFF_FFFF as DWORD, &devMode)
                            })
                        {
                            let hz = Int(devMode.dmDisplayFrequency)
                            if hz > 0 { refreshRate = hz }
                        }

                        // ── bounds / workArea / primary ─────────
                        let rc = info.rcMonitor
                        let wa = info.rcWork
                        let bounds = KSRect(
                            x: Int(rc.left), y: Int(rc.top),
                            width: Int(rc.right - rc.left), height: Int(rc.bottom - rc.top))
                        let workArea = KSRect(
                            x: Int(wa.left), y: Int(wa.top),
                            width: Int(wa.right - wa.left), height: Int(wa.bottom - wa.top))
                        let isPrimary = (info.dwFlags & DWORD(MONITORINFOF_PRIMARY)) != 0

                        // ── 고유 ID (hMonitor 포인터 값) ─────────
                        let id = String(
                            format: "%016llX",
                            UInt64(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hMon)))))

                        box.displays.append(
                            KSDisplayInfo(
                                id: id, name: deviceName,
                                bounds: bounds, workArea: workArea, scaleFactor: scale,
                                refreshRate: refreshRate, isPrimary: isPrimary))
                        return WindowsBool(true)
                    }, lpParam)
                if box.displays.isEmpty {
                    return .failure(
                        KSError(
                            code: .unsupportedPlatform,
                            message: "EnumDisplayMonitors returned no monitors"))
                }
                return .success(box.displays)
            }
            switch result {
            case .success(let v): return v
            case .failure(let e): throw e
            }
        }

        // MARK: currentDisplay — 특정 윈도우가 위치한 모니터 조회

        /// 주어진 `KSWindowHandle`이 현재 위치한 모니터의 `KSDisplayInfo`를
        /// 반환한다.
        ///
        /// 처리 순서:
        /// 1. `_resolveHWNDForCall`로 HWND 조회
        /// 2. `MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST)`로
        ///    윈도우와 가장 가까운 모니터 핸들 획득
        /// 3. 이후 정보 수집은 `listDisplays()`와 동일
        ///    (`GetMonitorInfoW` + `GetDpiForMonitor` + `EnumDisplaySettingsW`)
        public func currentDisplay(_ handle: KSWindowHandle) async throws(KSError) -> KSDisplayInfo {
            let hwnd: HWND = try Self._resolveHWNDForCall(handle, label: "currentDisplay")
            let result: Result<KSDisplayInfo, KSError> = Win32App.runOnUIThread {
                do {
                    guard let hMon = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST))
                    else {
                        throw KSError(
                            code: .unsupportedPlatform,
                            message: "MonitorFromWindow failed for '\(handle.label)'")
                    }
                    var info = MONITORINFOEXW()
                    info.cbSize = DWORD(MemoryLayout<MONITORINFOEXW>.size)
                    let ok: Bool = withUnsafeMutablePointer(to: &info) { p in
                        p.withMemoryRebound(to: MONITORINFO.self, capacity: 1) {
                            Bool(GetMonitorInfoW(hMon, $0))
                        }
                    }
                    guard ok else {
                        throw KSError(
                            code: .unsupportedPlatform,
                            message: "GetMonitorInfoW failed for '\(handle.label)'")
                    }
                    var dpiX: UINT = 96
                    var dpiY: UINT = 96
                    _ = GetDpiForMonitor(hMon, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)
                    let scale = Double(dpiX) / 96.0
                    let deviceName: String = withUnsafeBytes(of: info.szDevice) { raw in
                        guard let base = raw.bindMemory(to: WCHAR.self).baseAddress
                        else { return "" }
                        return String(decodingCString: base, as: UTF16.self)
                    }
                    var devMode = DEVMODEW()
                    devMode.dmSize = WORD(MemoryLayout<DEVMODEW>.size)
                    var refreshRate: Int? = nil
                    if Bool(
                        deviceName.withCString(encodedAs: UTF16.self) {
                            EnumDisplaySettingsW($0, 0xFFFF_FFFF as DWORD, &devMode)
                        })
                    {
                        let hz = Int(devMode.dmDisplayFrequency)
                        if hz > 0 { refreshRate = hz }
                    }
                    let rc = info.rcMonitor
                    let wa = info.rcWork
                    let bounds = KSRect(
                        x: Int(rc.left), y: Int(rc.top),
                        width: Int(rc.right - rc.left), height: Int(rc.bottom - rc.top))
                    let workArea = KSRect(
                        x: Int(wa.left), y: Int(wa.top),
                        width: Int(wa.right - wa.left), height: Int(wa.bottom - wa.top))
                    let isPrimary = (info.dwFlags & DWORD(MONITORINFOF_PRIMARY)) != 0
                    let id = String(
                        format: "%016llX",
                        UInt64(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hMon)))))
                    return .success(
                        KSDisplayInfo(
                            id: id, name: deviceName,
                            bounds: bounds, workArea: workArea, scaleFactor: scale,
                            refreshRate: refreshRate, isPrimary: isPrimary))
                } catch let e as KSError {
                    return .failure(e)
                } catch {
                    return .failure(KSError(code: .internal, message: "\(error)"))
                }
            }
            switch result {
            case .success(let v): return v
            case .failure(let e): throw e
            }
        }

        // MARK: - 동기 windowSync 헬퍼 (MainActor)

        /// `@MainActor` 격리된 동기 윈도우 조회 헬퍼.
        ///
        /// `startDrag()`나 `runOnUIThreadIsolated` 내부에서 사용된다.
        /// `window(for:)`와 동일하게 `KSWin32HandleRegistry` → `Win32App`
        /// 이중 조회를 수행한다.
        @MainActor
        internal func windowSync(for handle: KSWindowHandle) throws(KSError) -> Win32Window {
            guard let hwnd = KSWin32HandleRegistry.shared.hwnd(for: handle) else {
                throw KSError(
                    code: .windowCreationFailed,
                    message: "No window registered for label '\(handle.label)'")
            }
            guard let win = Win32App.shared.window(for: hwnd) else {
                throw KSError(
                    code: .windowCreationFailed,
                    message: "Win32Window not tracked for label '\(handle.label)'")
            }
            return win
        }
    }
#endif
