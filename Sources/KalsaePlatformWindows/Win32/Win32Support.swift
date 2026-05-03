#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore

    // MARK: - String helpers

    extension String {
        /// Executes `body` with a null-terminated UTF-16 pointer for this string.
        /// Used for every Win32 / WebView2 call that takes `LPCWSTR`.
        internal func withUTF16Pointer<R>(
            _ body: (UnsafePointer<UInt16>) throws -> R
        ) rethrows -> R {
            var utf16 = Array(self.utf16)
            utf16.append(0)
            // `utf16`에 항상 최소 1개의 원소(종료 삽입한 0)가 있므로
            // `baseAddress`는 논리적으로 non-nil이다. `unsafelyUnwrapped`로
            // 이 불변은 명시한다.
            return try utf16.withUnsafeBufferPointer { buf in
                try body(buf.baseAddress.unsafelyUnwrapped)
            }
        }
    }

    extension UnsafePointer<UInt16> {
        /// Builds a Swift `String` from a null-terminated UTF-16 buffer.
        internal func toString(maxLength: Int = 1024 * 1024) -> String {
            var length = 0
            while length < maxLength && self[length] != 0 { length += 1 }
            let buf = UnsafeBufferPointer(start: self, count: length)
            return String(decoding: buf, as: UTF16.self)
        }
    }

    /// Calls `body` with a null-terminated UTF-16 pointer for `s`, or with
    /// `nil` when `s` itself is `nil`. Used for Win32/WebView2 entry points
    /// that treat `NULL` as "use default".
    @inline(__always)
    internal func withOptionalUTF16<R>(
        _ s: String?,
        _ body: (UnsafePointer<UInt16>?) -> R
    ) -> R {
        guard let s else { return body(nil) }
        return s.withUTF16Pointer { body($0) }
    }

    // MARK: - HRESULT

    /// Thin wrapper around a Win32 `HRESULT`. `SUCCEEDED == hr >= 0`.
    internal struct KSHRESULT: Equatable {
        let value: Int32
        init(_ v: Int32) { self.value = v }
        var succeeded: Bool { value >= 0 }
        // E_NOINTERFACE (0x80004002): 런타임이 해당 인터페이스를 지원하지 않음.
        // 이 경우 핸들러를 조용히 건너뛴다.
        var isNotInterface: Bool { UInt32(bitPattern: value) == 0x80004002 }

        func throwIfFailed(
            _ code: KSError.Code = .platformInitFailed,
            _ context: @autoclosure () -> String
        ) throws(KSError) {
            guard succeeded else {
                throw KSError(
                    code: code,
                    message:
                        "\(context()) (HRESULT=0x\(String(UInt32(bitPattern: value), radix: 16, uppercase: true)))",
                    data: .int(Int(value)))
            }
        }
    }
#endif
