import Foundation

extension KSBuiltinCommands {
    // MARK: - FS arg / result types

    struct FSPathArg: Codable, Sendable {
        let path: String
    }
    struct FSWriteTextArg: Codable, Sendable {
        let path: String
        let contents: String
        let append: Bool?
    }
    struct FSWriteBytesArg: Codable, Sendable {
        let path: String
        /// Base64-encoded payload.
        let contents: String
        let append: Bool?
    }
    struct FSReadBytesResult: Codable, Sendable {
        /// Base64-encoded payload.
        let contents: String
        let length: Int
    }
    struct FSReadTextResult: Codable, Sendable {
        let contents: String
    }
    struct FSExistsResult: Codable, Sendable {
        let exists: Bool
        let isDirectory: Bool
    }
    struct FSMetadataResult: Codable, Sendable {
        let exists: Bool
        let isDirectory: Bool
        let size: Int64?
        let modifiedAtSecondsSince1970: Double?
        let createdAtSecondsSince1970: Double?
    }
    struct FSReadDirArg: Codable, Sendable {
        let path: String
        let recursive: Bool?
    }
    struct FSDirEntry: Codable, Sendable {
        let name: String
        let path: String
        let isDirectory: Bool
    }
    struct FSReadDirResult: Codable, Sendable {
        let entries: [FSDirEntry]
    }
    struct FSCreateDirArg: Codable, Sendable {
        let path: String
        let recursive: Bool?
    }
    struct FSRemoveArg: Codable, Sendable {
        let path: String
        let recursive: Bool?
    }
    struct FSRenameArg: Codable, Sendable {
        let from: String
        let to: String
    }
    struct FSCopyArg: Codable, Sendable {
        let from: String
        let to: String
        let overwrite: Bool?
    }

    /// Registers the `__ks.fs.*` command family. Every command validates
    /// its target path against `scope` after `$APP` / `$HOME` / `$DOCS` /
    /// `$TEMP` placeholder expansion. Operations on paths that fall
    /// outside the allow list throw `.fsScopeDenied`.
    ///
    /// The handler set is intentionally Tauri-compatible:
    ///   * `__ks.fs.readTextFile`   — UTF-8 text
    ///   * `__ks.fs.readFile`       — base64 bytes
    ///   * `__ks.fs.writeTextFile`  — UTF-8 text (append optional)
    ///   * `__ks.fs.writeFile`      — base64 bytes (append optional)
    ///   * `__ks.fs.exists`         — file-or-dir existence check
    ///   * `__ks.fs.metadata`       — size, mtime, ctime, kind
    ///   * `__ks.fs.readDir`        — directory listing (optional recursive)
    ///   * `__ks.fs.createDir`      — mkdir / mkdir -p
    ///   * `__ks.fs.remove`         — file or dir (recursive optional)
    ///   * `__ks.fs.rename`         — atomic move within filesystem
    ///   * `__ks.fs.copyFile`       — file copy with optional overwrite
    static func registerFSCommands(
        into registry: KSCommandRegistry,
        scope: KSFSScope,
        appDirectory: URL
    ) async {
        let ctx = KSFSScope.ExpansionContext.current(appDirectory: appDirectory)

        // 경로 검증을 한 곳에 모은다. 인자에 placeholder가 있을 수 있으므로
        // `$`-확장 후 절대 경로로 정규화한 뒤 scope에 묻는다.
        @Sendable
        func resolve(_ raw: String) throws(KSError) -> URL {
            let expanded = KSFSScope.expand(raw, in: ctx)
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            let absolute = url.path
            guard scope.permits(absolutePath: absolute, in: ctx) else {
                throw KSError(code: .fsScopeDenied,
                              message: "fs scope denies path '\(raw)'",
                              data: .string(absolute))
            }
            return url
        }

        await register(registry, "__ks.fs.readTextFile") { (args: FSPathArg) throws(KSError) -> FSReadTextResult in
            let url = try resolve(args.path)
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw KSError(code: .ioFailed,
                    message: "fs.readTextFile failed: \(error.localizedDescription)")
            }
            guard let s = String(data: data, encoding: .utf8) else {
                throw KSError(code: .ioFailed,
                    message: "fs.readTextFile: file is not valid UTF-8")
            }
            return FSReadTextResult(contents: s)
        }

        await register(registry, "__ks.fs.readFile") { (args: FSPathArg) throws(KSError) -> FSReadBytesResult in
            let url = try resolve(args.path)
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw KSError(code: .ioFailed,
                    message: "fs.readFile failed: \(error.localizedDescription)")
            }
            return FSReadBytesResult(
                contents: data.base64EncodedString(),
                length: data.count)
        }

        await register(registry, "__ks.fs.writeTextFile") { (args: FSWriteTextArg) throws(KSError) -> Empty in
            let url = try resolve(args.path)
            let data = Data(args.contents.utf8)
            do {
                if args.append == true, FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url, options: [.atomic])
                }
            } catch {
                throw KSError(code: .ioFailed,
                    message: "fs.writeTextFile failed: \(error.localizedDescription)")
            }
            return Empty()
        }

        await register(registry, "__ks.fs.writeFile") { (args: FSWriteBytesArg) throws(KSError) -> Empty in
            let url = try resolve(args.path)
            guard let data = Data(base64Encoded: args.contents) else {
                throw KSError(code: .invalidArgument,
                    message: "fs.writeFile: contents is not valid base64")
            }
            do {
                if args.append == true, FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url, options: [.atomic])
                }
            } catch {
                throw KSError(code: .ioFailed,
                    message: "fs.writeFile failed: \(error.localizedDescription)")
            }
            return Empty()
        }

        await register(registry, "__ks.fs.exists") { (args: FSPathArg) throws(KSError) -> FSExistsResult in
            let url = try resolve(args.path)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path, isDirectory: &isDir)
            return FSExistsResult(exists: exists, isDirectory: isDir.boolValue)
        }

        await register(registry, "__ks.fs.metadata") { (args: FSPathArg) throws(KSError) -> FSMetadataResult in
            let url = try resolve(args.path)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path, isDirectory: &isDir)
            guard exists else {
                return FSMetadataResult(
                    exists: false, isDirectory: false,
                    size: nil, modifiedAtSecondsSince1970: nil,
                    createdAtSecondsSince1970: nil)
            }
            let attrs: [FileAttributeKey: Any]
            do {
                attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            } catch {
                throw KSError(code: .ioFailed,
                    message: "fs.metadata failed: \(error.localizedDescription)")
            }
            let size = (attrs[.size] as? NSNumber)?.int64Value
            let mod = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
            let created = (attrs[.creationDate] as? Date)?.timeIntervalSince1970
            return FSMetadataResult(
                exists: true,
                isDirectory: isDir.boolValue,
                size: size,
                modifiedAtSecondsSince1970: mod,
                createdAtSecondsSince1970: created)
        }

        await register(registry, "__ks.fs.readDir") { (args: FSReadDirArg) throws(KSError) -> FSReadDirResult in
            let root = try resolve(args.path)
            let recursive = args.recursive == true

            // 재귀 enumerator를 사용해 항목별로 scope를 재검증한다.
            let fm = FileManager.default
            var entries: [FSDirEntry] = []
            if recursive {
                guard let it = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]) else {
                    throw KSError(code: .ioFailed,
                        message: "fs.readDir: cannot enumerate '\(root.path)'")
                }
                for case let url as URL in it {
                    let standardized = url.standardizedFileURL.path
                    guard scope.permits(absolutePath: standardized, in: ctx) else { continue }
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    entries.append(FSDirEntry(
                        name: url.lastPathComponent,
                        path: standardized,
                        isDirectory: isDir))
                }
            } else {
                let urls: [URL]
                do {
                    urls = try fm.contentsOfDirectory(
                        at: root,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles])
                } catch {
                    throw KSError(code: .ioFailed,
                        message: "fs.readDir failed: \(error.localizedDescription)")
                }
                for url in urls {
                    let standardized = url.standardizedFileURL.path
                    guard scope.permits(absolutePath: standardized, in: ctx) else { continue }
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    entries.append(FSDirEntry(
                        name: url.lastPathComponent,
                        path: standardized,
                        isDirectory: isDir))
                }
            }
            return FSReadDirResult(entries: entries)
        }

        await register(registry, "__ks.fs.createDir") { (args: FSCreateDirArg) throws(KSError) -> Empty in
            let url = try resolve(args.path)
            do {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: args.recursive ?? true)
            } catch {
                throw KSError(code: .ioFailed,
                    message: "fs.createDir failed: \(error.localizedDescription)")
            }
            return Empty()
        }

        await register(registry, "__ks.fs.remove") { (args: FSRemoveArg) throws(KSError) -> Empty in
            let url = try resolve(args.path)
            // 디렉터리이면서 recursive 플래그가 false인 경우 항목이 비어 있는지 검사.
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: url.path, isDirectory: &isDir)
            guard exists else {
                throw KSError(code: .ioFailed,
                    message: "fs.remove: path does not exist")
            }
            if isDir.boolValue, args.recursive != true {
                let count = (try? FileManager.default
                    .contentsOfDirectory(atPath: url.path).count) ?? 0
                if count > 0 {
                    throw KSError(code: .ioFailed,
                        message: "fs.remove: directory not empty (set recursive=true)")
                }
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw KSError(code: .ioFailed,
                    message: "fs.remove failed: \(error.localizedDescription)")
            }
            return Empty()
        }

        await register(registry, "__ks.fs.rename") { (args: FSRenameArg) throws(KSError) -> Empty in
            let src = try resolve(args.from)
            let dst = try resolve(args.to)
            do {
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                throw KSError(code: .ioFailed,
                    message: "fs.rename failed: \(error.localizedDescription)")
            }
            return Empty()
        }

        await register(registry, "__ks.fs.copyFile") { (args: FSCopyArg) throws(KSError) -> Empty in
            let src = try resolve(args.from)
            let dst = try resolve(args.to)
            let fm = FileManager.default
            if fm.fileExists(atPath: dst.path) {
                if args.overwrite == true {
                    do {
                        try fm.removeItem(at: dst)
                    } catch {
                        throw KSError(code: .ioFailed,
                            message: "fs.copyFile: cannot overwrite destination: \(error.localizedDescription)")
                    }
                } else {
                    throw KSError(code: .ioFailed,
                        message: "fs.copyFile: destination exists (set overwrite=true)")
                }
            }
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                throw KSError(code: .ioFailed,
                    message: "fs.copyFile failed: \(error.localizedDescription)")
            }
            return Empty()
        }
    }
}
