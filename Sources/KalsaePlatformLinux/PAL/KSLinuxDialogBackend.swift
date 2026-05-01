#if os(Linux)
internal import CKalsaeGtk
internal import Glibc
public import KalsaeCore
public import Foundation

/// Linux implementation of `KSDialogBackend` using GTK4 native dialogs.
public struct KSLinuxDialogBackend: KSDialogBackend, Sendable {
    public init() {}

    // MARK: - KSDialogBackend

    public func openFile(options: KSOpenFileOptions,
                         parent: KSWindowHandle?) async throws(KSError) -> [URL] {
        await withCheckedContinuation { (cont: CheckedContinuation<[URL], Never>) in
            Task { @MainActor in
                let host = resolveHost(parent)
                let (names, globs) = buildFilters(options.filters)
                let title = options.title ?? "Open"
                let dir   = options.defaultDirectory?.path

                let box = FilesBox(cont)
                let ptr = Unmanaged.passRetained(box).toOpaque()

                names.withUnsafeCStringArray { namePtr in
                    globs.withUnsafeCStringArray { globPtr in
                        ks_gtk_dialog_open_files(
                            host?.hostPtr,
                            title,
                            dir,
                            namePtr,
                            globPtr,
                            Int32(options.filters.count),
                            options.allowsMultiple ? 1 : 0,
                            { paths, ctx in
                                let b = Unmanaged<FilesBox>.fromOpaque(ctx!).takeRetainedValue()
                                if let paths {
                                    var urls: [URL] = []
                                    var i = 0
                                    while let p = paths[i] {
                                        urls.append(URL(fileURLWithPath: String(cString: p)))
                                        i += 1
                                    }
                                    b.cont.resume(returning: urls)
                                } else {
                                    b.cont.resume(returning: [])
                                }
                            },
                            ptr)
                    }
                }
            }
        }
    }

    public func saveFile(options: KSSaveFileOptions,
                         parent: KSWindowHandle?) async throws(KSError) -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            Task { @MainActor in
                let host  = resolveHost(parent)
                let (names, globs) = buildFilters(options.filters)
                let title = options.title ?? "Save"
                let dir   = options.defaultDirectory?.path
                let name  = options.defaultFileName

                let box = FileBox(cont)
                let ptr = Unmanaged.passRetained(box).toOpaque()

                names.withUnsafeCStringArray { namePtr in
                    globs.withUnsafeCStringArray { globPtr in
                        ks_gtk_dialog_save_file(
                            host?.hostPtr,
                            title,
                            dir,
                            name,
                            namePtr,
                            globPtr,
                            Int32(options.filters.count),
                            { path, ctx in
                                let b = Unmanaged<FileBox>.fromOpaque(ctx!).takeRetainedValue()
                                b.cont.resume(returning: path.map {
                                    URL(fileURLWithPath: String(cString: $0))
                                })
                            },
                            ptr)
                    }
                }
            }
        }
    }

    public func selectFolder(options: KSSelectFolderOptions,
                             parent: KSWindowHandle?) async throws(KSError) -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            Task { @MainActor in
                let host  = resolveHost(parent)
                let title = options.title ?? "Select Folder"
                let dir   = options.defaultDirectory?.path

                let box = FileBox(cont)
                let ptr = Unmanaged.passRetained(box).toOpaque()
                ks_gtk_dialog_select_folder(
                    host?.hostPtr,
                    title,
                    dir,
                    { path, ctx in
                        let b = Unmanaged<FileBox>.fromOpaque(ctx!).takeRetainedValue()
                        b.cont.resume(returning: path.map {
                            URL(fileURLWithPath: String(cString: $0))
                        })
                    },
                    ptr)
            }
        }
    }

    @discardableResult
    public func message(_ options: KSMessageOptions,
                        parent: KSWindowHandle?) async throws(KSError) -> KSMessageResult {
        await withCheckedContinuation { (cont: CheckedContinuation<KSMessageResult, Never>) in
            Task { @MainActor in
                let host    = resolveHost(parent)
                let kind    = kindCode(options.kind)
                let buttons = buttonsCode(options.buttons)

                let box = MsgBox(cont, buttons: options.buttons)
                let ptr = Unmanaged.passRetained(box).toOpaque()
                ks_gtk_dialog_message(
                    host?.hostPtr,
                    Int32(kind),
                    options.title,
                    options.message,
                    options.detail,
                    Int32(buttons),
                    { result, ctx in
                        let b = Unmanaged<MsgBox>.fromOpaque(ctx!).takeRetainedValue()
                        b.cont.resume(returning: b.decodeResult(Int(result)))
                    },
                    ptr)
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func resolveHost(_ handle: KSWindowHandle?) -> GtkWebViewHost? {
        let reg = KSLinuxHandleRegistry.shared
        if let h = handle {
            return reg.entry(for: h)?.host
        }
        return reg.allHandles().first.flatMap { reg.entry(for: $0) }?.host
    }

    private func buildFilters(_ filters: [KSFileFilter]) -> ([String], [String]) {
        let names = filters.map { $0.name }
        let globs = filters.map { f in f.extensions.map { "*.\($0)" }.joined(separator: ";") }
        return (names, globs)
    }

    private func kindCode(_ kind: KSMessageOptions.Kind) -> Int {
        switch kind {
        case .info:     return 0
        case .warning:  return 1
        case .error:    return 2
        case .question: return 3
        }
    }

    private func buttonsCode(_ buttons: KSMessageOptions.Buttons) -> Int {
        switch buttons {
        case .ok:          return 0
        case .okCancel:    return 1
        case .yesNo:       return 2
        case .yesNoCancel: return 3
        }
    }
}

// MARK: - Continuation boxes

// @unchecked: GTK async callback box \u2014 continuation captured for deferred resumption
private final class FilesBox: @unchecked Sendable {
    let cont: CheckedContinuation<[URL], Never>
    init(_ cont: CheckedContinuation<[URL], Never>) { self.cont = cont }
}

// @unchecked: GTK async callback box \u2014 continuation captured for deferred resumption
private final class FileBox: @unchecked Sendable {
    let cont: CheckedContinuation<URL?, Never>
    init(_ cont: CheckedContinuation<URL?, Never>) { self.cont = cont }
}

private final class MsgBox: @unchecked Sendable {
    // @unchecked: GTK async callback box \u2014 continuation captured for deferred resumption
    let cont: CheckedContinuation<KSMessageResult, Never>
    let buttons: KSMessageOptions.Buttons

    init(_ cont: CheckedContinuation<KSMessageResult, Never>,
         buttons: KSMessageOptions.Buttons) {
        self.cont    = cont
        self.buttons = buttons
    }

    func decodeResult(_ code: Int) -> KSMessageResult {
        switch code {
        case 0:
            return buttons == .yesNo || buttons == .yesNoCancel ? .yes : .ok
        case 1:
            switch buttons {
            case .ok:          return .ok      // shouldn't happen
            case .okCancel:    return .cancel
            case .yesNo:       return .no
            case .yesNoCancel: return .no
            }
        case 2:
            return .cancel
        default:
            return .cancel
        }
    }
}

// MARK: - C string array helper

private extension Array where Element == String {
    /// Calls `body` with a NULL-terminated `const char *const *` that is
    /// valid only for the duration of the call.
    func withUnsafeCStringArray<R>(
        _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> R
    ) -> R {
        if isEmpty { return body(nil) }
        // strdup each string so the pointers are stable during `body`.
        let cStrings: [UnsafeMutablePointer<CChar>] = self.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var ptrs: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
        ptrs.append(nil)
        return ptrs.withUnsafeBufferPointer { buf in body(buf.baseAddress) }
    }
}
#endif
