#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    import Foundation

    // MARK: - KSWindowsWindowBackend + Display enumeration

    extension KSWindowsWindowBackend {

        // MARK: listDisplays

        public func listDisplays() async throws(KSError) -> [KSDisplayInfo] {
            let result: Result<[KSDisplayInfo], KSError> = await MainActor.run {
                final class DisplayBox { var displays: [KSDisplayInfo] = [] }
                let box = DisplayBox()
                let lpParam = LPARAM(Int(bitPattern: Unmanaged.passUnretained(box).toOpaque()))
                EnumDisplayMonitors(
                    nil, nil,
                    { hMon, _, _, lpParam -> WindowsBool in
                        guard let rawPtr = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: Int(lpParam))),
                            let hMon
                        else { return WindowsBool(true) }
                        let box = Unmanaged<DisplayBox>.fromOpaque(rawPtr).takeUnretainedValue()
                        var info = MONITORINFOEXW()
                        info.cbSize = DWORD(MemoryLayout<MONITORINFOEXW>.size)
                        let ok: Bool = withUnsafeMutablePointer(to: &info) { p in
                            p.withMemoryRebound(to: MONITORINFO.self, capacity: 1) {
                                Bool(GetMonitorInfoW(hMon, $0))
                            }
                        }
                        guard ok else { return WindowsBool(true) }
                        var dpiX: UINT = 96
                        var dpiY: UINT = 96
                        _ = GetDpiForMonitor(hMon, MDT_EFFECTIVE_DPI, &dpiX, &dpiY)
                        let scale = Double(dpiX) / 96.0
                        let deviceName: String = withUnsafeBytes(of: info.szDevice) { raw in
                            guard let base = raw.bindMemory(to: WCHAR.self).baseAddress else { return "" }
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

        // MARK: currentDisplay

        public func currentDisplay(_ handle: KSWindowHandle) async throws(KSError) -> KSDisplayInfo {
            let result: Result<KSDisplayInfo, KSError> = await MainActor.run {
                do {
                    let win = try self.windowSync(for: handle)
                    guard let hwnd = win.hwnd else {
                        throw KSError(
                            code: .windowCreationFailed,
                            message: "currentDisplay: '\(handle.label)' has no HWND")
                    }
                    guard let hMon = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST)) else {
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
                        guard let base = raw.bindMemory(to: WCHAR.self).baseAddress else { return "" }
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

        // MARK: - Private sync helper (MainActor)

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
