#if os(Windows)
    internal import WinSDK
    internal import CKalsaeWV2
    public import KalsaeCore
    public import Foundation

    /// Win32 셸 백엔드 구현체 (`KSShellBackend`).
    ///
    /// `openExternal` / `showItemInFolder`는 `ShellExecuteW`로 실행하고,
    /// `moveToTrash`는 `SHFileOperationW(FO_DELETE | FOF_ALLOWUNDO)`로
    /// 휴지통 이동을 구현한다.
    public struct KSWindowsShellBackend: KSShellBackend, Sendable {
        public init() {}

        public func openExternal(_ url: URL) async throws(KSError) {
            let s = url.absoluteString
            let result: Result<Void, KSError> = Win32App.runOnUIThread {
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
            let result: Result<Void, KSError> = Win32App.runOnUIThread {
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
            // SHFileOperationW 는 내부적으로 자체 모달 메시지 루프를 돌리므로
            // UI 스레드에서 호출하면 우리 펌프에 재진입(reentrant)하여
            // 데드락이 발생한다. 호출자(Task) 스레드에서 직접 실행한다.
            // OleInitialize 는 per-thread idempotent (Dialog backend 와 동일).
            _ = KSWV2_OleInitializeOnce()

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
                throw KSError(
                    code: .ioFailed,
                    message: "SHFileOperationW(FO_DELETE) failed (rc=\(hr)) for \(path)",
                    data: .int(Int(hr)))
            }
        }
    }
#endif
