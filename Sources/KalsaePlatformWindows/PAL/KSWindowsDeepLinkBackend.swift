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
            let s = try Self.normalizeScheme(scheme)
            let exe = try Self.resolveModulePath()
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
            guard let s = try? Self.normalizeScheme(scheme),
                let exe = try? Self.resolveModulePath()
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

        private static func resolveModulePath() throws(KSError) -> String {
            var capacity = 1024
            while capacity <= 32768 {
                var buf = [UInt16](repeating: 0, count: capacity)
                let rc = GetModuleFileNameW(nil, &buf, DWORD(capacity))
                if rc == 0 {
                    let err = Int(GetLastError())
                    throw KSError(
                        code: .ioFailed,
                        message: "GetModuleFileNameW failed (\(err))",
                        data: .int(err))
                }
                if Int(rc) == capacity {
                    capacity *= 2
                    continue
                }
                return String(decoding: buf.prefix(Int(rc)), as: UTF16.self)
            }
            throw KSError(
                code: .ioFailed,
                message: "GetModuleFileNameW: path > 32K characters")
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
                    ptr.baseAddress!.withMemoryRebound(
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
                    bp.baseAddress!.withMemoryRebound(
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
