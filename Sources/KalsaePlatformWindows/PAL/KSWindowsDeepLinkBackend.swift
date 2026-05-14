#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    internal import Foundation
    // HKCU\Software\Classes\<scheme>\shell\open\command
    //   (Default) = "\"<exePath>\" \"%1\""
    //
    // explorer는 URL을 그대로 %1로 넘긴다.
    ///
    /// ```text
    /// HKCU\Software\Classes\<scheme>
    ///     (default)         = "URL:<identifier>"
    ///     URL Protocol      = ""
    ///     shell\open\command
    ///         (default)     = "\"<exe>\" \"%1\""
    /// ```
    ///
    /// `register(scheme:)` writes that subtree. `unregister(scheme:)`
    /// removes it via `RegDeleteTreeW`. `isRegistered(scheme:)` reads back
    /// the `command` default and string-compares against the running EXE
    /// path.
    public struct KSWindowsDeepLinkBackend: KSDeepLinkBackend, Sendable {
        /// App identifier. Used in the `(default)` value of the scheme key
        /// (`"URL:<identifier>"`) so multiple Kalsae apps can coexist.
        public let identifier: String

        public init(identifier: String) {
            self.identifier = identifier
        }

        public func register(scheme: String) throws(KSError) {
            if KSWindowsAppPackageContext.isMSIXPackaged() {
                // RFC-008 P2: MSIX 메니페스트 `windows.protocol` 선언이 이미
                // 스견하므로 HKCU\Software\Classes 쓰기는 안전하게 생략.
                // 수신 경로는 그대로 (CommandLine.arguments) 동작.
                print(
                    "⚠  KSWindowsDeepLinkBackend.register(\"\(scheme)\"): no-op under MSIX "
                        + "(scheme is declared in AppxManifest `windows.protocol`).")
                return
            }
            let s = try Self.normalizeScheme(scheme)
            let exe = try KSWindowsModule.resolvePath()
            let command = "\"\(exe)\" \"%1\""

            let base = "Software\\Classes\\\(s)"
            try Self.writeStringValue(
                keyPath: base, valueName: "", value: "URL:\(identifier)")
            try Self.writeStringValue(
                keyPath: base, valueName: "URL Protocol", value: "")
            try Self.writeStringValue(
                keyPath: "\(base)\\shell\\open\\command",
                valueName: "", value: command)
        }

        public func unregister(scheme: String) throws(KSError) {
            if KSWindowsAppPackageContext.isMSIXPackaged() {
                print(
                    "⚠  KSWindowsDeepLinkBackend.unregister(\"\(scheme)\"): no-op under MSIX.")
                return
            }
            let s = try Self.normalizeScheme(scheme)
            let path = "Software\\Classes\\\(s)"
            let hr = path.withUTF16Pointer { sub in
                RegDeleteTreeW(HKEY_CURRENT_USER, sub)
            }
            if hr != ERROR_SUCCESS && hr != ERROR_FILE_NOT_FOUND {
                throw KSError(
                    code: .ioFailed,
                    message: "RegDeleteTreeW failed (\(hr)) for \(path)",
                    data: .int(Int(hr)))
            }
        }

        public func isRegistered(scheme: String) -> Bool {
            if KSWindowsAppPackageContext.isMSIXPackaged() {
                // MSIX 에서는 OS 가 manifest 선언을 자동 등록한다. PAL 에서는
                // 시스템 상태 확인이 불가능하지는 않지만 일관성을 위해 true 를
                // 반환해 JS 레이어가 “등록됨” 으로 가정하도록 한다.
                return true
            }
            guard let s = try? Self.normalizeScheme(scheme),
                let exe = try? KSWindowsModule.resolvePath()
            else { return false }
            let path = "Software\\Classes\\\(s)\\shell\\open\\command"
            guard let value = Self.readStringValue(keyPath: path, valueName: "")
            else { return false }
            // 등록된 명령은 `"<exe>" "%1"` 형태이므로 EXE 경로 substring 매칭으로 충분.
            return value.range(of: exe, options: .caseInsensitive) != nil
        }

        public func currentLaunchURLs(forSchemes schemes: [String]) -> [String] {
            let args = Array(CommandLine.arguments.dropFirst())
            return extractURLs(fromArgs: args, forSchemes: schemes)
        }

        public func extractURLs(
            fromArgs args: [String], forSchemes schemes: [String]
        ) -> [String] {
            let lowerSchemes = Set(schemes.map { $0.lowercased() })
            var out: [String] = []
            for a in args {
                // 가벼운 검사: `scheme:` prefix가 등록 목록에 있으면 채택.
                // URL(string:)을 통해 이중 검증해 잘못된 입력을 거른다.
                guard let colon = a.firstIndex(of: ":") else { continue }
                let scheme = a[..<colon].lowercased()
                guard lowerSchemes.contains(scheme),
                    URL(string: a) != nil
                else { continue }
                out.append(a)
            }
            return out
        }

        // MARK: - Internals

        static func normalizeScheme(_ scheme: String) throws(KSError) -> String {
            let s = scheme.lowercased()
            // RFC 3986: scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
            guard let first = s.first, first.isLetter else {
                throw KSError(
                    code: .invalidArgument,
                    message: "deep-link scheme must start with an ASCII letter: '\(scheme)'")
            }
            for ch in s {
                if !(ch.isLetter || ch.isNumber || ch == "+" || ch == "-" || ch == ".") {
                    throw KSError(
                        code: .invalidArgument,
                        message: "deep-link scheme has invalid character '\(ch)': '\(scheme)'")
                }
            }
            return s
        }

        private static func writeStringValue(
            keyPath: String, valueName: String, value: String
        ) throws(KSError) {
            var hKey: HKEY? = nil
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

        private static func readStringValue(keyPath: String, valueName: String) -> String? {
            var hKey: HKEY? = nil
            // KEY_READ
            let openHr = keyPath.withUTF16Pointer { sub in
                RegOpenKeyExW(HKEY_CURRENT_USER, sub, 0, DWORD(0x20019), &hKey)
            }
            guard openHr == ERROR_SUCCESS, let hKey else { return nil }
            defer { _ = RegCloseKey(hKey) }
            var size: DWORD = 0
            var typ: DWORD = 0
            let probeHr = valueName.withUTF16Pointer { name -> LONG in
                RegQueryValueExW(hKey, name, nil, &typ, nil, &size)
            }
            guard probeHr == ERROR_SUCCESS, size > 0 else { return nil }
            let count = Int(size) / MemoryLayout<UInt16>.size
            var buf = [UInt16](repeating: 0, count: count)
            let readHr = valueName.withUTF16Pointer { name -> LONG in
                buf.withUnsafeMutableBufferPointer { bp -> LONG in
                    guard let base = bp.baseAddress else { return LONG(ERROR_INVALID_PARAMETER) }
                    return base.withMemoryRebound(
                        to: BYTE.self, capacity: Int(size)
                    ) { bytes in
                        RegQueryValueExW(hKey, name, nil, &typ, bytes, &size)
                    }
                }
            }
            guard readHr == ERROR_SUCCESS else { return nil }
            // Trailing NUL 제거.
            let trimmed = buf.prefix(while: { $0 != 0 })
            return String(decoding: trimmed, as: UTF16.self)
        }
    }
#endif
