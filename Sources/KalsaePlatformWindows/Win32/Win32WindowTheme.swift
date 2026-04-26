#if os(Windows)
internal import WinSDK
public import KalsaeCore

extension Win32Window {

    /// Applies a theme via DWM's immersive dark-mode attribute. Tries
    /// the documented attribute index first (20, Win10 19H2+) and falls
    /// back to the older index (19) for earlier builds. Failures are
    /// silent — theming is best-effort.
    func setTheme(_ theme: KSWindowTheme) {
        guard let hwnd else { return }
        // DWMWA_USE_IMMERSIVE_DARK_MODE 값은 Win10 1903+ / 19h2에서 20,
        // 이전 빌드는 19었다. 둘 다 시도한다.
        var enable: Int32 = {
            switch theme {
            case .dark: return 1
            case .light: return 0
            case .system:
                // HKCU\...\Themes\Personalize에서 AppsUseLightTheme 읽음.
                return Self.systemPrefersDark() ? 1 : 0
            }
        }()
        let DWMWA_USE_IMMERSIVE_DARK_MODE: DWORD = 20
        let DWMWA_USE_IMMERSIVE_DARK_MODE_OLD: DWORD = 19
        let size = DWORD(MemoryLayout<Int32>.size)
        var hr = withUnsafePointer(to: &enable) { ptr -> Int32 in
            DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ptr, size)
        }
        if hr < 0 {
            hr = withUnsafePointer(to: &enable) { ptr -> Int32 in
                DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, ptr, size)
            }
        }
        _ = hr
    }

    /// Reads `HKCU\...\Themes\Personalize\AppsUseLightTheme` to infer
    /// the current system preference. Defaults to `false` (light) on any
    /// access failure.
    fileprivate static func systemPrefersDark() -> Bool {
        let subkey = #"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"#
        let valueName = "AppsUseLightTheme"
        var hkey: HKEY?
        // KEY_READ 매크로는 Swift WinSDK 오버레이에 import되지 않는다.
        // 문서화된 수치값을 직접 쓴다 (STANDARD_RIGHTS_READ |
        // KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY) &
        // ~SYNCHRONIZE = 0x20019.
        let KEY_READ_NUMERIC: DWORD = 0x20019
        let openHR = subkey.withUTF16Pointer { sk -> Int32 in
            RegOpenKeyExW(HKEY_CURRENT_USER, sk, 0, KEY_READ_NUMERIC, &hkey)
        }
        guard openHR == 0, let hkey else { return false }
        defer { _ = RegCloseKey(hkey) }
        var data: DWORD = 1
        var len = DWORD(MemoryLayout<DWORD>.size)
        let qHR = valueName.withUTF16Pointer { vn -> Int32 in
            withUnsafeMutablePointer(to: &data) { dataPtr in
                dataPtr.withMemoryRebound(to: BYTE.self, capacity: Int(len)) { bytes in
                    RegQueryValueExW(hkey, vn, nil, nil, bytes, &len)
                }
            }
        }
        guard qHR == 0 else { return false }
        return data == 0
    }
}
#endif
