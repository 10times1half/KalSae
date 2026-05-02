/// 네이티브 다이얼로그. `parent`가 제공되면 모든 호출은 해당 창에 대해 모달이다.
public import Foundation

public protocol KSDialogBackend: Sendable {
    func openFile(
        options: KSOpenFileOptions,
        parent: KSWindowHandle?
    ) async throws(KSError) -> [URL]

    func saveFile(
        options: KSSaveFileOptions,
        parent: KSWindowHandle?
    ) async throws(KSError) -> URL?

    func selectFolder(
        options: KSSelectFolderOptions,
        parent: KSWindowHandle?
    ) async throws(KSError) -> URL?

    @discardableResult
    func message(
        _ options: KSMessageOptions,
        parent: KSWindowHandle?
    ) async throws(KSError) -> KSMessageResult
}
public struct KSFileFilter: Codable, Sendable, Equatable {
    public var name: String
    public var extensions: [String]
    public init(name: String, extensions: [String]) {
        self.name = name
        self.extensions = extensions
    }
}
public struct KSOpenFileOptions: Codable, Sendable, Equatable {
    public var title: String?
    public var defaultDirectory: URL?
    public var filters: [KSFileFilter]
    public var allowsMultiple: Bool

    public init(
        title: String? = nil,
        defaultDirectory: URL? = nil,
        filters: [KSFileFilter] = [],
        allowsMultiple: Bool = false
    ) {
        self.title = title
        self.defaultDirectory = defaultDirectory
        self.filters = filters
        self.allowsMultiple = allowsMultiple
    }
}
public struct KSSaveFileOptions: Codable, Sendable, Equatable {
    public var title: String?
    public var defaultDirectory: URL?
    public var defaultFileName: String?
    public var filters: [KSFileFilter]

    public init(
        title: String? = nil,
        defaultDirectory: URL? = nil,
        defaultFileName: String? = nil,
        filters: [KSFileFilter] = []
    ) {
        self.title = title
        self.defaultDirectory = defaultDirectory
        self.defaultFileName = defaultFileName
        self.filters = filters
    }
}
public struct KSSelectFolderOptions: Codable, Sendable, Equatable {
    public var title: String?
    public var defaultDirectory: URL?
    public init(title: String? = nil, defaultDirectory: URL? = nil) {
        self.title = title
        self.defaultDirectory = defaultDirectory
    }
}
public struct KSMessageOptions: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case info, warning, error, question
    }
    public enum Buttons: String, Codable, Sendable {
        case ok, okCancel, yesNo, yesNoCancel
    }
    public var kind: Kind
    public var title: String
    public var message: String
    public var detail: String?
    public var buttons: Buttons

    public init(
        kind: Kind,
        title: String,
        message: String,
        detail: String? = nil,
        buttons: Buttons = .ok
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.detail = detail
        self.buttons = buttons
    }
}
public enum KSMessageResult: String, Codable, Sendable {
    case ok, cancel, yes, no
}
