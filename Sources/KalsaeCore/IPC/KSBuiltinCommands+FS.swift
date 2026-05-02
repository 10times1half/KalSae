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
        /// Base64 인코딩된 페이로드.
        let contents: String
        let append: Bool?
    }
    struct FSReadBytesResult: Codable, Sendable {
        /// Base64 인코딩된 페이로드.
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

    /// `__ks.fs.*` 명령 패밀리를 등록한다. 모든 명령은 `$APP` / `$HOME` /
    /// `$DOCS` / `$TEMP` 플레이스홀더 확장 후 `scope`에 대해 대상 경로를
    /// 검증한다. 허용 목록 외부의 경로에 대한 작업은 `.fsScopeDenied`를 던진다.
    ///
    /// 핸들러 집합은 의도적으로 Tauri 호환으로 설계되었다:
    ///   * `__ks.fs.readTextFile`   — UTF-8 텍스트 읽기
    ///   * `__ks.fs.readFile`       — base64 바이트 읽기
    ///   * `__ks.fs.writeTextFile`  — UTF-8 텍스트 쓰기 (추가 선택)
    ///   * `__ks.fs.writeFile`      — base64 바이트 쓰기 (추가 선택)
    ///   * `__ks.fs.exists`         — 파일/디렉토리 존재 확인
    ///   * `__ks.fs.metadata`       — 크기, 수정 시간, 생성 시간, 종류
    ///   * `__ks.fs.readDir`        — 디렉토리 목록 (재귀 선택)
    ///   * `__ks.fs.createDir`      — mkdir / mkdir -p
    ///   * `__ks.fs.remove`         — 파일 또는 디렉토리 삭제 (재귀 선택)
    ///   * `__ks.fs.rename`         — 파일 시스템 내 원자적 이동
    ///   * `__ks.fs.copyFile`       — 덮어쓰기 선택 가능한 파일 복사
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
                throw KSError(
                    code: .fsScopeDenied,
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
                throw KSError(
                    code: .ioFailed,
                    message: "fs.readTextFile failed: \(error.localizedDescription)")
            }
            guard let s = String(data: data, encoding: .utf8) else {
                throw KSError(
                    code: .ioFailed,
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
                throw KSError(
                    code: .ioFailed,
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
                throw KSError(
                    code: .ioFailed,
                    message: "fs.writeTextFile failed: \(error.localizedDescription)")
            }
            return Empty()
        }

        await register(registry, "__ks.fs.writeFile") { (args: FSWriteBytesArg) throws(KSError) -> Empty in
            let url = try resolve(args.path)
            guard let data = Data(base64Encoded: args.contents) else {
                throw KSError(
                    code: .invalidArgument,
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
                throw KSError(
                    code: .ioFailed,
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
                throw KSError(
                    code: .ioFailed,
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
                guard
                    let it = fm.enumerator(
                        at: root,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles])
                else {
                    throw KSError(
                        code: .ioFailed,
                        message: "fs.readDir: cannot enumerate '\(root.path)'")
                }
                for case let url as URL in it {
                    let standardized = url.standardizedFileURL.path
                    guard scope.permits(absolutePath: standardized, in: ctx) else { continue }
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    entries.append(
                        FSDirEntry(
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
                    throw KSError(
                        code: .ioFailed,
                        message: "fs.readDir failed: \(error.localizedDescription)")
                }
                for url in urls {
                    let standardized = url.standardizedFileURL.path
                    guard scope.permits(absolutePath: standardized, in: ctx) else { continue }
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    entries.append(
                        FSDirEntry(
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
                throw KSError(
                    code: .ioFailed,
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
                throw KSError(
                    code: .ioFailed,
                    message: "fs.remove: path does not exist")
            }
            if isDir.boolValue, args.recursive != true {
                let count =
                    (try? FileManager.default
                        .contentsOfDirectory(atPath: url.path).count) ?? 0
                if count > 0 {
                    throw KSError(
                        code: .ioFailed,
                        message: "fs.remove: directory not empty (set recursive=true)")
                }
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw KSError(
                    code: .ioFailed,
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
                throw KSError(
                    code: .ioFailed,
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
                        throw KSError(
                            code: .ioFailed,
                            message: "fs.copyFile: cannot overwrite destination: \(error.localizedDescription)")
                    }
                } else {
                    throw KSError(
                        code: .ioFailed,
                        message: "fs.copyFile: destination exists (set overwrite=true)")
                }
            }
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                throw KSError(
                    code: .ioFailed,
                    message: "fs.copyFile failed: \(error.localizedDescription)")
            }
            return Empty()
        }
    }
}
