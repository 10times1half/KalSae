#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    public import Foundation

    /// Win32 implementation of `KSShellBackend`.
    ///
    /// Backed by `ShellExecuteW` for `openExternal`/`showItemInFolder` and
    /// `SHFileOperationW` (FO_DELETE | FOF_ALLOWUNDO) for `moveToTrash`.
    public struct KSWindowsShellBackend: KSShellBackend, Sendable {
        public init() {}

        public func openExternal(_ url: URL) async throws(KSError) {
            let s = url.absoluteString
            let result: Result<Void, KSError> = await MainActor.run {
                let verb = "open"
                let rc: Int = verb.withUTF16Pointer { verbPtr in
                    s.withUTF16Pointer { urlPtr -> Int in
                        let h = ShellExecuteW(nil, verbPtr, urlPtr, nil, nil, Int32(SW_SHOWNORMAL))
                        // ShellExecuteW는 HINSTANCE를 반환한다. 문서화된 계약상
                        // 32 이하의 값은 에러를 의미한다.
                        guard let h else { return 0 }
                        return Int(bitPattern: UnsafeRawPointer(h))
                    }
                }
                if rc <= 32 {
                    return .failure(
                        KSError(
                            code: .ioFailed,
                            message: "ShellExecuteW failed (\(rc)) for url \(s)",
                            data: .int(rc)))
                }
                return .success(())
            }
            try result.unwrap()
        }

        public func showItemInFolder(_ url: URL) async throws(KSError) {
            // ShellExecuteW("explorer.exe", "/select,<path>")를 사용해 탐색기를
            // 해당 항목이 선택된 상태로 연다. SHOpenFolderAndSelectItems는
            // PIDL 구성이 필요해 면 더 무겁지만, 이 방식은 모든 지원
            // 대상 Windows에서 동작한다.
            let path = url.path
            // Security: a path containing a literal `"` would break the /select,
            // argument quoting, allowing argument injection into explorer.exe.
            guard !path.contains("\"") else {
                throw KSError(
                    code: .invalidArgument,
                    message: "showItemInFolder: path contains illegal quote character")
            }
            let result: Result<Void, KSError> = await MainActor.run {
                let app = "explorer.exe"
                let args = "/select,\"\(path)\""
                let rc: Int = app.withUTF16Pointer { appPtr in
                    args.withUTF16Pointer { argsPtr -> Int in
                        let h = ShellExecuteW(nil, nil, appPtr, argsPtr, nil, Int32(SW_SHOWNORMAL))
                        guard let h else { return 0 }
                        return Int(bitPattern: UnsafeRawPointer(h))
                    }
                }
                if rc <= 32 {
                    return .failure(
                        KSError(
                            code: .ioFailed,
                            message: "ShellExecuteW(\"explorer.exe /select,\(path)\") failed (\(rc))",
                            data: .int(rc)))
                }
                return .success(())
            }
            try result.unwrap()
        }

        public func moveToTrash(_ url: URL) async throws(KSError) {
            let path = url.path
            let result: Result<Void, KSError> = await MainActor.run {
                // SHFILEOPSTRUCT는 이중 null 종료된 경로 목록을 요구한다.
                var utf16 = Array(path.utf16)
                utf16.append(0)  // single null at end of path
                utf16.append(0)  // double null to mark end of list

                let hr: Int32 = utf16.withUnsafeBufferPointer { buf -> Int32 in
                    var op = SHFILEOPSTRUCTW()
                    op.wFunc = UINT(FO_DELETE)
                    op.pFrom = buf.baseAddress
                    op.fFlags = FILEOP_FLAGS(FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI)
                    return Int32(SHFileOperationW(&op))
                }
                if hr != 0 {
                    return .failure(
                        KSError(
                            code: .ioFailed,
                            message: "SHFileOperationW(FO_DELETE) failed (rc=\(hr)) for \(path)",
                            data: .int(Int(hr))))
                }
                return .success(())
            }
            try result.unwrap()
        }
    }
#endif
