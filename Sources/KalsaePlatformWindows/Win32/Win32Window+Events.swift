#if os(Windows)
internal import WinSDK

// MARK: - Win32Window event emit + payload types
//
// `Win32Window+WndProc.swift`가 추상 메시지를 가공해 JS 이벤트로
// 발사한다. 모든 페이로드는 Codable & Sendable 구조체로 분리해
// JSON 형태가 안정적이도록 한다(`__KS_.listen`이 그대로 받는다).

extension Win32Window {

    /// Convenience used by WndProc: forwards `(name, payload)` to the
    /// installed sink, swallowing failures (sink may not be wired yet
    /// during early WM_SIZE bursts before the webview is created).
    @inline(__always)
    internal func emit<E: Encodable & Sendable>(
        _ name: String, _ payload: E
    ) {
        eventSink?(name, payload)
    }

    // MARK: - Payload structs

    internal struct WindowSizePayload: Encodable, Sendable {
        let w: Int
        let h: Int
    }

    internal struct WindowPointPayload: Encodable, Sendable {
        let x: Int
        let y: Int
    }

    internal struct EmptyPayload: Encodable, Sendable {}

    internal struct ThemePayload: Encodable, Sendable {
        let theme: String  // "light" | "dark"
    }

    internal struct DPIPayload: Encodable, Sendable {
        let dpi: Int
        let scale: Double
    }

    // MARK: - Theme detection

    /// Reads `HKCU\…\Themes\Personalize\AppsUseLightTheme` and returns
    /// `"light"` / `"dark"`. Defaults to `"light"` if the key is missing
    /// (older Windows versions or restricted environments).
    internal func readSystemAppsTheme() -> String {
        let subKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"
        let valueName = "AppsUseLightTheme"
        var hKey: HKEY? = nil
        let openHr = subKey.withUTF16Pointer { sub in
            // KEY_READ = STANDARD_RIGHTS_READ | KEY_QUERY_VALUE |
            //           KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY = 0x20019.
            RegOpenKeyExW(HKEY_CURRENT_USER, sub, 0, DWORD(0x20019), &hKey)
        }
        guard openHr == ERROR_SUCCESS, let hKey else { return "light" }
        defer { _ = RegCloseKey(hKey) }
        var data: DWORD = 1
        var size: DWORD = DWORD(MemoryLayout<DWORD>.size)
        var typ: DWORD = 0
        let qHr = valueName.withUTF16Pointer { name -> LONG in
            withUnsafeMutablePointer(to: &data) { dataPtr -> LONG in
                dataPtr.withMemoryRebound(to: BYTE.self, capacity: Int(size)) { bytes in
                    RegQueryValueExW(hKey, name, nil, &typ, bytes, &size)
                }
            }
        }
        guard qHr == ERROR_SUCCESS else { return "light" }
        return data == 0 ? "dark" : "light"
    }
}
#endif
