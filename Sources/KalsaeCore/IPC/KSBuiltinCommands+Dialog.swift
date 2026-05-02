import Foundation

extension KSBuiltinCommands {
    /// `__ks.dialog.*` 핸들러를 등록한다 — `openFile`, `saveFile`,
    /// `selectFolder`, `message`. 모달 생명주기는 PAL `KSDialogBackend`가
    /// 담당하므로 이 레이어는 얇은 Codable 어댑터에 불과하다.
    ///
    /// JS 형태 (플랫폼 간 이식성을 위해 경로를 문자열로 전달):
    /// ```
    /// __KS_.dialog.openFile({ filters, allowsMultiple? }) → { paths: [String] }
    /// __KS_.dialog.saveFile({ defaultFileName?, filters }) → { path: String? }
    /// __KS_.dialog.selectFolder({ title?, defaultDirectory? }) → { path: String? }
    /// __KS_.dialog.message({ kind, title, message, buttons }) → { result }
    /// ```
    /// `defaultDirectory`(입력)은 경로 문자열을 받는다. 반환되는 `path` 필드는
    /// POSIX 플랫폼에서는 POSIX 스타일, Windows에서는 네이티브 스타일
    /// (예: `C:\\Users\\…`)이다.
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
        await register(registry, "__ks.dialog.selectFolder") {
            (args: SelectFolderArg) throws(KSError) -> SaveFileResult in
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
