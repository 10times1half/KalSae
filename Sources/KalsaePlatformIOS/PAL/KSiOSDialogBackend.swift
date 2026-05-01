#if os(iOS)
public import KalsaeCore
public import Foundation

public struct KSiOSDialogBackend: KSDialogBackend, Sendable {
    public init() {}

    public func openFile(
        options: KSOpenFileOptions,
        parent: KSWindowHandle?
    ) async throws(KSError) -> [URL] {
        _ = (options, parent)
        return []
    }

    public func saveFile(
        options: KSSaveFileOptions,
        parent: KSWindowHandle?
    ) async throws(KSError) -> URL? {
        _ = (options, parent)
        return nil
    }

    public func selectFolder(
        options: KSSelectFolderOptions,
        parent: KSWindowHandle?
    ) async throws(KSError) -> URL? {
        _ = (options, parent)
        return nil
    }

    @discardableResult
    public func message(
        _ options: KSMessageOptions,
        parent: KSWindowHandle?
    ) async throws(KSError) -> KSMessageResult {
        _ = (options, parent)
        return .ok
    }
}
#endif
