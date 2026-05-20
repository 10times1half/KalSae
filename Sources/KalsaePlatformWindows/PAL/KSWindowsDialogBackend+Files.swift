#if os(Windows)
    internal import WinSDK
    internal import CKalsaeWV2
    internal import KalsaeCore
    internal import Foundation

    // MARK: - KSWindowsDialogBackend file dialog implementation
    //
    // 모던 Vista+ Common Item Dialog (`IFileOpenDialog` / `IFileSaveDialog`)을
    // `kswv2_dialog.cpp` C++ 쉬밌을 통해 호출한다. 레거시
    // `GetOpenFileNameW` / `GetSaveFileNameW` / `SHBrowseForFolderW`를 대체.
    // 긴 경로(>MAX_PATH) 지원, 기본 폴더는 `IShellItem`로 정확하게 지정,
    // 폴더 선택은 `FOS_PICKFOLDERS` 사용.

    extension KSWindowsDialogBackend {

        // NOTE: The dialog helpers are intentionally `nonisolated` even though
        // they are only invoked on the Win32 UI thread. Under Swift 6, closures
        // created inside `@MainActor` functions are inferred `@MainActor`. When
        // such a closure is later invoked by a nonisolated generic stdlib helper
        // (e.g. `Array.map`, `Array.withUnsafeBufferPointer`,
        // `String.withCString`), the runtime inserts `swift_task_checkIsolated`
        // which calls `dispatch_assert_queue(main_queue)`. The Win32 UI thread
        // is NOT Swift's dispatch main queue (Kalsae owns its own UI thread,
        // see `Win32App.unsafelyAssumeMainActor`), so the assert traps with
        // `STATUS_ILLEGAL_INSTRUCTION` (0xC000001D) at `dispatch.dll+0x1EE52`.
        // Marking these helpers `nonisolated` avoids the inference. Callers in
        // this file (`openFileOnUI` etc.) remain `@MainActor` for API clarity.

        nonisolated
        static func _openFileOnMain(
            options: KSOpenFileOptions,
            parentHWND: UnsafeMutableRawPointer?
        ) -> [URL] {
            ensureCOMInitialized()
            let title = options.title ?? "Open"
            let dir = options.defaultDirectory?.path ?? ""

            return withFilterSpecs(options.filters) { specs, count -> [URL] in
                title.withUTF16Pointer { titlePtr in
                    dir.withUTF16Pointer { dirPtr in
                        var paths: UnsafeMutablePointer<UnsafeMutablePointer<wchar_t>?>? = nil
                        var written: Int32 = 0
                        let titleArg: UnsafePointer<wchar_t>? = title.isEmpty ? nil : titlePtr
                        let dirArg: UnsafePointer<wchar_t>? = dir.isEmpty ? nil : dirPtr
                        let hr = KSWV2_DialogOpenFile(
                            parentHWND,
                            titleArg, dirArg,
                            specs, count,
                            options.allowsMultiple ? 1 : 0,
                            &paths, &written)
                        if hr != 0 || written <= 0 || paths == nil { return [] }
                        return drainPathArray(paths!, count: Int(written))
                    }
                }
            }
        }

        nonisolated
        static func _saveFileOnMain(
            options: KSSaveFileOptions,
            parentHWND: UnsafeMutableRawPointer?
        ) -> URL? {
            ensureCOMInitialized()
            let title = options.title ?? "Save"
            let dir = options.defaultDirectory?.path ?? ""
            let name = options.defaultFileName ?? ""

            return withFilterSpecs(options.filters) { specs, count -> URL? in
                title.withUTF16Pointer { titlePtr in
                    dir.withUTF16Pointer { dirPtr in
                        name.withUTF16Pointer { namePtr in
                            var out: UnsafeMutablePointer<wchar_t>? = nil
                            var chosen: Int32 = 0
                            let titleArg: UnsafePointer<wchar_t>? = title.isEmpty ? nil : titlePtr
                            let dirArg: UnsafePointer<wchar_t>? = dir.isEmpty ? nil : dirPtr
                            let nameArg: UnsafePointer<wchar_t>? = name.isEmpty ? nil : namePtr
                            let hr = KSWV2_DialogSaveFile(
                                parentHWND,
                                titleArg, dirArg, nameArg,
                                specs, count,
                                &out, &chosen)
                            if hr != 0 || chosen == 0 || out == nil { return nil }
                            let path = UnsafePointer(out!).toString()
                            KSWV2_Free(out)
                            return path.isEmpty ? nil : URL(fileURLWithPath: path)
                        }
                    }
                }
            }
        }

        nonisolated
        static func _selectFolderOnMain(
            options: KSSelectFolderOptions,
            parentHWND: UnsafeMutableRawPointer?
        ) -> URL? {
            ensureCOMInitialized()
            let title = options.title ?? "Select folder"
            let dir = options.defaultDirectory?.path ?? ""

            return title.withUTF16Pointer { titlePtr -> URL? in
                dir.withUTF16Pointer { dirPtr -> URL? in
                    var out: UnsafeMutablePointer<wchar_t>? = nil
                    var chosen: Int32 = 0
                    let titleArg: UnsafePointer<wchar_t>? = title.isEmpty ? nil : titlePtr
                    let dirArg: UnsafePointer<wchar_t>? = dir.isEmpty ? nil : dirPtr
                    let hr = KSWV2_DialogSelectFolder(
                        parentHWND,
                        titleArg, dirArg,
                        &out, &chosen)
                    if hr != 0 || chosen == 0 || out == nil { return nil }
                    let path = UnsafePointer(out!).toString()
                    KSWV2_Free(out)
                    return path.isEmpty ? nil : URL(fileURLWithPath: path)
                }
            }
        }

        // MARK: - 헬퍼

        /// COM은 STA로 초기화되어 있어야 IFileOpenDialog가 동작한다.
        /// `KSWV2_OleInitializeOnce`는 호출 스레드별 idempotent.
        nonisolated
        private static func ensureCOMInitialized() {
            _ = KSWV2_OleInitializeOnce()
        }

        /// 필터 입력을 `KSWV2DialogFilter` 배열로 변환해 작업을 실행한다.
        /// UTF-16 버퍼는 호출 동안 메모리에 고정된다.
        nonisolated
        private static func withFilterSpecs<R>(
            _ filters: [KSFileFilter],
            _ body: (UnsafePointer<KSWV2DialogFilter>?, Int32) -> R
        ) -> R {
            let entries: [KSFileFilter] =
                filters.isEmpty
                ? [KSFileFilter(name: "All Files", extensions: ["*"])]
                : filters

            // UTF-16 버퍼를 직접 할당해 호출 끝까지 안정된 포인터를 보장.
            var allocations: [UnsafeMutablePointer<UInt16>] = []
            allocations.reserveCapacity(entries.count * 2)
            defer {
                for p in allocations { p.deallocate() }
            }
            var specs = [KSWV2DialogFilter](
                repeating: KSWV2DialogFilter(name: nil, spec: nil),
                count: entries.count)

            for (i, f) in entries.enumerated() {
                let namePtr = allocateUTF16NullTerminated(f.name)
                let pattern = f.extensions
                    .map { $0.hasPrefix("*.") ? $0 : "*.\($0)" }
                    .joined(separator: ";")
                let specPtr = allocateUTF16NullTerminated(
                    pattern.isEmpty ? "*.*" : pattern)
                allocations.append(namePtr)
                allocations.append(specPtr)
                specs[i] = KSWV2DialogFilter(
                    name: UnsafePointer(namePtr),
                    spec: UnsafePointer(specPtr))
            }
            return specs.withUnsafeBufferPointer { sp in
                body(sp.baseAddress, Int32(entries.count))
            }
        }

        nonisolated
        private static func allocateUTF16NullTerminated(
            _ s: String
        ) -> UnsafeMutablePointer<UInt16> {
            let units = Array(s.utf16)
            let p = UnsafeMutablePointer<UInt16>.allocate(capacity: units.count + 1)
            for (i, u) in units.enumerated() {
                p[i] = u
            }
            p[units.count] = 0
            return p
        }

        /// `KSWV2_DialogOpenFile`이 반환한 wchar_t** 배열을 URL로 변환하고
        /// 메모리를 해제한다.
        nonisolated
        private static func drainPathArray(
            _ array: UnsafeMutablePointer<UnsafeMutablePointer<wchar_t>?>,
            count: Int
        ) -> [URL] {
            var urls: [URL] = []
            urls.reserveCapacity(count)
            for i in 0..<count {
                if let p = array[i] {
                    let path = UnsafePointer(p).toString()
                    if !path.isEmpty {
                        urls.append(URL(fileURLWithPath: path))
                    }
                    KSWV2_Free(p)
                }
            }
            KSWV2_Free(array)
            return urls
        }
    }
#endif
