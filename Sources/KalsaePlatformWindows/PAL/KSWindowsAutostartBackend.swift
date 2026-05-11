#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    internal import Foundation

    /// Win32 implementation of the autostart ("launch on login") feature.
    ///
    /// Backed by `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, which
    /// is the same key Tauri's `plugin-autostart` writes on Windows. The
    /// value name is the app identifier (`KSAppInfo.identifier`); the value
    /// data is the absolute path of the running executable, optionally
    /// followed by extra arguments declared in `KSAutostartConfig.args`.
    ///
    /// All three operations are synchronous and idempotent. Errors surface
    /// as `KSError(.ioFailed)` carrying the underlying Win32 status.
    public struct KSWindowsAutostartBackend: KSAutostartBackend, Sendable {
        /// App identifier — used as the registry value name. Must not
        /// contain `\` or `/` (Win32 forbids those in value names).
        public let identifier: String
        /// Extra command-line args appended after the EXE path.
        public let args: [String]

        public init(identifier: String, args: [String] = []) {
            self.identifier = identifier
            self.args = args
        }

        private static let runKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"

        /// Registers the current process (resolved via `GetModuleFileNameW`)
        /// to launch on user login. Overwrites any existing value with the
        /// same identifier.
        public func enable() throws(KSError) {
            if KSWindowsAppPackageContext.isMSIXPackaged() {
                // RFC-008 P2: MSIX 메니페스트 `windows.startupTask` 선언이
                // 대신 처리하고, 사용자가 Settings > Apps > Startup 에서
                // 토글하도록 안내. PAL 에서는 no-op + 성공 반환.
                print(
                    "⚠  KSWindowsAutostartBackend.enable(): no-op under MSIX "
                    + "(autostart is managed by AppxManifest `windows.startupTask`). "
                    + "User must enable via Settings > Apps > Startup.")
                return
            }
            let exe = try KSWindowsModule.resolvePath()
            // 인자 결합: 실행 파일 경로는 항상 큰따옴표로 감싸 공백을 보호.
            var command = "\"\(exe)\""
            for a in args {
                // 인자에 공백/큰따옴표가 있으면 CommandLineToArgvW 규칙에 맞춰
                // 다시 양 끝을 따옴표로 감싸고 내부 따옴표는 백슬래시로 이스케이프한다.
                let needsQuote = a.contains(" ") || a.contains("\"")
                if needsQuote {
                    let escaped = a.replacingOccurrences(of: "\"", with: "\\\"")
                    command += " \"\(escaped)\""
                } else {
                    command += " \(a)"
                }
            }
            try Self.writeStringValue(
                keyPath: Self.runKey,
                valueName: identifier,
                value: command)
        }

        /// Removes the registry value. Succeeds silently if the value does
        /// not exist.
        public func disable() throws(KSError) {
            if KSWindowsAppPackageContext.isMSIXPackaged() {
                print(
                    "⚠  KSWindowsAutostartBackend.disable(): no-op under MSIX "
                    + "(managed by AppxManifest).")
                return
            }
            try Self.deleteValue(keyPath: Self.runKey, valueName: identifier)
        }

        /// Returns `true` when the registry value exists, regardless of its
        /// data (an empty value still counts).
        public func isEnabled() -> Bool {
            if KSWindowsAppPackageContext.isMSIXPackaged() {
                // MSIX 에서는 상태 조회 API 가 다르다 (StartupTask.GetStatus,
                // WinRT). 어쩌다 false 를 반환해 JS 레이어가 “껌짐” 으로
                // 착각하는 것도 스토어 정책상 필요 시 사용자가 Settings 에서
                // 토글하도록 하는 흐름이므로 안전하다.
                return false
            }
            var hKey: HKEY? = nil
            // KEY_READ
            let openHr = Self.runKey.withUTF16Pointer { sub in
                RegOpenKeyExW(HKEY_CURRENT_USER, sub, 0, DWORD(0x20019), &hKey)
            }
            guard openHr == ERROR_SUCCESS, let hKey else { return false }
            defer { _ = RegCloseKey(hKey) }
            var size: DWORD = 0
            var typ: DWORD = 0
            let qHr = identifier.withUTF16Pointer { name -> LONG in
                RegQueryValueExW(hKey, name, nil, &typ, nil, &size)
            }
            return qHr == ERROR_SUCCESS
        }

        // MARK: - Internals

        private static func writeStringValue(
            keyPath: String, valueName: String, value: String
        ) throws(KSError) {
            var hKey: HKEY? = nil
            // KEY_SET_VALUE | KEY_QUERY_VALUE.
            let openHr = keyPath.withUTF16Pointer { sub -> LONG in
                var disposition: DWORD = 0
                // KEY_WRITE
                return RegCreateKeyExW(
                    HKEY_CURRENT_USER, sub, 0, nil,
                    DWORD(REG_OPTION_NON_VOLATILE),
                    DWORD(0x20006), nil, &hKey, &disposition)
            }
            guard openHr == ERROR_SUCCESS, let hKey else {
                throw KSError(
                    code: .ioFailed,
                    message: "RegCreateKeyExW failed (\(openHr)) for \(keyPath)",
                    data: .int(Int(openHr)))
            }
            defer { _ = RegCloseKey(hKey) }
            let utf16 = Array(value.utf16) + [0]
            let byteCount = DWORD(utf16.count * MemoryLayout<UInt16>.size)
            let setHr = valueName.withUTF16Pointer { name -> LONG in
                utf16.withUnsafeBufferPointer { ptr -> LONG in
                    guard let base = ptr.baseAddress else { return LONG(ERROR_INVALID_PARAMETER) }
                    return base.withMemoryRebound(
                        to: BYTE.self, capacity: Int(byteCount)
                    ) { bytes in
                        RegSetValueExW(hKey, name, 0, DWORD(REG_SZ), bytes, byteCount)
                    }
                }
            }
            if setHr != ERROR_SUCCESS {
                throw KSError(
                    code: .ioFailed,
                    message: "RegSetValueExW failed (\(setHr))",
                    data: .int(Int(setHr)))
            }
        }

        private static func deleteValue(
            keyPath: String, valueName: String
        ) throws(KSError) {
            var hKey: HKEY? = nil
            let openHr = keyPath.withUTF16Pointer { sub in
                RegOpenKeyExW(HKEY_CURRENT_USER, sub, 0, DWORD(KEY_SET_VALUE), &hKey)
            }
            guard openHr == ERROR_SUCCESS, let hKey else {
                // 키가 없으면 이미 disable 상태로 간주.
                if openHr == ERROR_FILE_NOT_FOUND { return }
                throw KSError(
                    code: .ioFailed,
                    message: "RegOpenKeyExW failed (\(openHr)) for \(keyPath)",
                    data: .int(Int(openHr)))
            }
            defer { _ = RegCloseKey(hKey) }
            let delHr = valueName.withUTF16Pointer { name in
                RegDeleteValueW(hKey, name)
            }
            if delHr != ERROR_SUCCESS && delHr != ERROR_FILE_NOT_FOUND {
                throw KSError(
                    code: .ioFailed,
                    message: "RegDeleteValueW failed (\(delHr))",
                    data: .int(Int(delHr)))
            }
        }
    }
#endif
