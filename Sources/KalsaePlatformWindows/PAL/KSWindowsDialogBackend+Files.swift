#if os(Windows)
internal import WinSDK
public import KalsaeCore
public import Foundation

// MARK: - KSWindowsDialogBackend file dialog implementation
//
// `KSWindowsDialogBackend`의 파일 다이얼로그 UI-스레드 구현부.
// `_openFileOnMain` / `_saveFileOnMain` / `_selectFolderOnMain`은
// 메인 파일이 노출하는 `*OnUI` 진입점에서 위임받아 호출한다.
// 보조 헬퍼(`makeFilterString` / `parseOpenFileResult`)도 함께 둔다.

extension KSWindowsDialogBackend {

    @MainActor
    static func _openFileOnMain(
        options: KSOpenFileOptions,
        parent: KSWindowHandle?
    ) -> [URL] {
        let parentHWND = parent.flatMap { KSWin32HandleRegistry.shared.hwnd(for: $0) }
        let bufLen = 64 * 1024
        var buffer = [UInt16](repeating: 0, count: bufLen)
        let filterUTF16 = makeFilterString(options.filters)

        let success: Bool = filterUTF16.withUnsafeBufferPointer { filterPtr in
            let title = options.title ?? "Open"
            let initialDir = options.defaultDirectory?.path ?? ""

            return title.withUTF16Pointer { titlePtr in
                initialDir.withUTF16Pointer { initialPtr in
                    var ofn = OPENFILENAMEW()
                    ofn.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
                    ofn.hwndOwner = parentHWND
                    ofn.lpstrFilter = filterPtr.baseAddress
                    ofn.lpstrTitle = titlePtr
                    ofn.lpstrInitialDir = initialPtr
                    ofn.nMaxFile = DWORD(bufLen)
                    var flags: DWORD = DWORD(OFN_FILEMUSTEXIST) |
                                       DWORD(OFN_PATHMUSTEXIST) |
                                       DWORD(OFN_EXPLORER)
                    if options.allowsMultiple {
                        flags |= DWORD(OFN_ALLOWMULTISELECT)
                    }
                    ofn.Flags = flags
                    return buffer.withUnsafeMutableBufferPointer { bufPtr in
                        ofn.lpstrFile = bufPtr.baseAddress
                        return GetOpenFileNameW(&ofn)
                    }
                }
            }
        }

        guard success else { return [] }
        return parseOpenFileResult(buffer: buffer, allowsMultiple: options.allowsMultiple)
    }

    @MainActor
    static func _saveFileOnMain(
        options: KSSaveFileOptions,
        parent: KSWindowHandle?
    ) -> URL? {
        let parentHWND = parent.flatMap { KSWin32HandleRegistry.shared.hwnd(for: $0) }
        let bufLen = 4096
        var buffer = [UInt16](repeating: 0, count: bufLen)
        if let name = options.defaultFileName {
            for (i, c) in name.utf16.enumerated() where i < bufLen - 1 {
                buffer[i] = c
            }
        }
        let filterUTF16 = makeFilterString(options.filters)

        let success: Bool = filterUTF16.withUnsafeBufferPointer { filterPtr in
            let title = options.title ?? "Save"
            let initialDir = options.defaultDirectory?.path ?? ""

            return title.withUTF16Pointer { titlePtr in
                initialDir.withUTF16Pointer { initialPtr in
                    var ofn = OPENFILENAMEW()
                    ofn.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
                    ofn.hwndOwner = parentHWND
                    ofn.lpstrFilter = filterPtr.baseAddress
                    ofn.lpstrTitle = titlePtr
                    ofn.lpstrInitialDir = initialPtr
                    ofn.nMaxFile = DWORD(bufLen)
                    ofn.Flags = DWORD(OFN_PATHMUSTEXIST) |
                                DWORD(OFN_OVERWRITEPROMPT) |
                                DWORD(OFN_EXPLORER)
                    return buffer.withUnsafeMutableBufferPointer { bufPtr in
                        ofn.lpstrFile = bufPtr.baseAddress
                        return GetSaveFileNameW(&ofn)
                    }
                }
            }
        }

        guard success else { return nil }
        return buffer.withUnsafeBufferPointer { bp -> URL? in
            guard let base = bp.baseAddress else { return nil }
            let path = base.toString()
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
    }

    @MainActor
    static func _selectFolderOnMain(
        options: KSSelectFolderOptions,
        parent: KSWindowHandle?
    ) -> URL? {
        let parentHWND = parent.flatMap { KSWin32HandleRegistry.shared.hwnd(for: $0) }
        let title = options.title ?? "Select folder"

        return title.withUTF16Pointer { titlePtr -> URL? in
            var bi = BROWSEINFOW()
            bi.hwndOwner = parentHWND
            bi.lpszTitle = titlePtr
            bi.ulFlags = UINT(BIF_RETURNONLYFSDIRS) | UINT(BIF_NEWDIALOGSTYLE)

            guard let pidl = SHBrowseForFolderW(&bi) else { return nil }
            defer { CoTaskMemFree(pidl) }

            var pathBuf = [UInt16](repeating: 0, count: Int(MAX_PATH) + 1)
            let ok = pathBuf.withUnsafeMutableBufferPointer { ptr -> Bool in
                guard let base = ptr.baseAddress else { return false }
                return SHGetPathFromIDListW(pidl, base)
            }
            guard ok else { return nil }
            // pathBuf는 MAX_PATH+1 고정 크기로 항상 non-empty → baseAddress는 non-nil.
            let path = pathBuf.withUnsafeBufferPointer {
                $0.baseAddress.unsafelyUnwrapped.toString()
            }
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
    }

    // MARK: - Filter / result helpers

    /// Builds a `GetOpenFileName`-style filter:
    /// `"All Files\0*.*\0Images\0*.png;*.jpg\0\0"`
    fileprivate static func makeFilterString(_ filters: [KSFileFilter]) -> [UInt16] {
        var u16: [UInt16] = []
        let entries = filters.isEmpty
            ? [KSFileFilter(name: "All Files", extensions: ["*"])]
            : filters
        for f in entries {
            for c in f.name.utf16 { u16.append(c) }
            u16.append(0)
            let pattern = f.extensions
                .map { $0.hasPrefix("*.") ? $0 : "*.\($0)" }
                .joined(separator: ";")
            for c in pattern.utf16 { u16.append(c) }
            u16.append(0)
        }
        u16.append(0)        // double-null terminator
        return u16
    }

    /// Parses the multi-select buffer returned by `GetOpenFileNameW`. The
    /// classic format is `"<dir>\0<file1>\0<file2>\0\0"` for multi-select,
    /// or just `"<full path>\0"` for single select.
    fileprivate static func parseOpenFileResult(
        buffer: [UInt16], allowsMultiple: Bool
    ) -> [URL] {
        // null 바이트로 분리.
        var pieces: [String] = []
        var start = 0
        for i in 0..<buffer.count {
            if buffer[i] == 0 {
                if start == i { break }     // empty piece → end
                let slice = buffer[start..<i]
                pieces.append(String(decoding: slice, as: UTF16.self))
                start = i + 1
            }
        }

        if pieces.isEmpty { return [] }

        if !allowsMultiple || pieces.count == 1 {
            // 단일 프레임의 전체 경로.
            return [URL(fileURLWithPath: pieces[0])]
        }

        // 다중 선택: 첫 조각은 디렉터리, 나머지는 파일 이름.
        let dir = pieces[0]
        let dirURL = URL(fileURLWithPath: dir)
        return pieces.dropFirst().map { dirURL.appendingPathComponent($0) }
    }
}
#endif
