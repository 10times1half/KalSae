import Foundation

extension KSBuiltinCommands {
    /// Registers `__ks.dialog.*` handlers — `openFile`, `saveFile`,
    /// `selectFolder`, `message`. The PAL `KSDialogBackend` already
    /// owns modal lifecycle, so this layer is a thin Codable adapter.
    ///
    /// JS shape (path-as-string for portability across platforms):
    /// ```
    /// __KS_.dialog.openFile({ filters, allowsMultiple? }) → { paths: [String] }
    /// __KS_.dialog.saveFile({ defaultFileName?, filters }) → { path: String? }
    /// __KS_.dialog.selectFolder({ title?, defaultDirectory? }) → { path: String? }
    /// __KS_.dialog.message({ kind, title, message, buttons }) → { result }
    /// ```
    /// `defaultDirectory` (input) accepts a path string. Returned `path`
    /// fields are POSIX-style on POSIX platforms and Windows-native
    /// (e.g. `C:\\Users\\…`) on Windows.
    static func registerDialogCommands(
        into registry: KSCommandRegistry,
        dialogs: any KSDialogBackend,
        resolver: WindowResolver
    ) async {
        await register(registry, "__ks.dialog.openFile") { (args: OpenFileArg) throws(KSError) -> OpenFileResult in
            let parent = try? await resolver.resolve(window: args.window)
            let opts = KSOpenFileOptions(
                title: args.title,
                defaultDirectory: args.defaultDirectory.flatMap(Self.dirURL),
                filters: args.filters ?? [],
                allowsMultiple: args.allowsMultiple ?? false)
            let urls = try await dialogs.openFile(options: opts, parent: parent)
            return OpenFileResult(paths: urls.map(\.path))
        }
        await register(registry, "__ks.dialog.saveFile") { (args: SaveFileArg) throws(KSError) -> SaveFileResult in
            let parent = try? await resolver.resolve(window: args.window)
            let opts = KSSaveFileOptions(
                title: args.title,
                defaultDirectory: args.defaultDirectory.flatMap(Self.dirURL),
                defaultFileName: args.defaultFileName,
                filters: args.filters ?? [])
            let url = try await dialogs.saveFile(options: opts, parent: parent)
            return SaveFileResult(path: url?.path)
        }
        await register(registry, "__ks.dialog.selectFolder") { (args: SelectFolderArg) throws(KSError) -> SaveFileResult in
            let parent = try? await resolver.resolve(window: args.window)
            let opts = KSSelectFolderOptions(
                title: args.title,
                defaultDirectory: args.defaultDirectory.flatMap(Self.dirURL))
            let url = try await dialogs.selectFolder(options: opts, parent: parent)
            return SaveFileResult(path: url?.path)
        }
        await register(registry, "__ks.dialog.message") { (args: MessageArg) throws(KSError) -> MessageResult in
            let parent = try? await resolver.resolve(window: args.window)
            let opts = KSMessageOptions(
                kind: args.kind,
                title: args.title,
                message: args.message,
                detail: args.detail,
                buttons: args.buttons ?? .ok)
            let r = try await dialogs.message(opts, parent: parent)
            return MessageResult(result: r)
        }
    }

    @inline(__always)
    private static func dirURL(_ path: String) -> URL? {
        path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - Wire types

    struct OpenFileArg: Codable, Sendable {
        let title: String?
        let defaultDirectory: String?
        let filters: [KSFileFilter]?
        let allowsMultiple: Bool?
        let window: String?
    }
    struct SaveFileArg: Codable, Sendable {
        let title: String?
        let defaultDirectory: String?
        let defaultFileName: String?
        let filters: [KSFileFilter]?
        let window: String?
    }
    struct SelectFolderArg: Codable, Sendable {
        let title: String?
        let defaultDirectory: String?
        let window: String?
    }
    struct MessageArg: Codable, Sendable {
        let kind: KSMessageOptions.Kind
        let title: String
        let message: String
        let detail: String?
        let buttons: KSMessageOptions.Buttons?
        let window: String?
    }
    struct OpenFileResult: Codable, Sendable {
        let paths: [String]
    }
    struct SaveFileResult: Codable, Sendable {
        let path: String?
    }
    struct MessageResult: Codable, Sendable {
        let result: KSMessageResult
    }
}
