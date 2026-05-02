#if os(iOS)
    public import KalsaeCore
    public import Foundation

    /// `KSDialogBackend`의 iOS 핸들러 주입형 구현체.
    ///
    /// iOS 다이얼로그(파일 선택, 메시지 등)는 `UIDocumentPickerViewController` 등
    /// UIKit 측에서 처리해야 한다. UIKit 호스트가 아래 핸들러를 부팅 전에 설정하면
    /// JS `__ks.dialog.*` 명령이 해당 핸들러를 통해 동작한다.
    ///
    /// 핸들러가 설정되지 않은 경우 모든 메서드는 `.unsupportedPlatform`을 throw한다.
    // @unchecked: NSLock + UIKit 메인 스레드 어피니티 — actor 부적합
    public final class KSiOSDialogBackend: KSDialogBackend, @unchecked Sendable {
        private let lock = NSLock()

        // MARK: - Injectable handlers (set by UIKit host)

        public var onOpenFile: ((KSOpenFileOptions, KSWindowHandle?) async -> [URL])? {
            get { lock.withLock { _onOpenFile } }
            set { lock.withLock { _onOpenFile = newValue } }
        }
        private var _onOpenFile: ((KSOpenFileOptions, KSWindowHandle?) async -> [URL])?

        public var onSaveFile: ((KSSaveFileOptions, KSWindowHandle?) async -> URL?)? {
            get { lock.withLock { _onSaveFile } }
            set { lock.withLock { _onSaveFile = newValue } }
        }
        private var _onSaveFile: ((KSSaveFileOptions, KSWindowHandle?) async -> URL?)?

        public var onSelectFolder: ((KSSelectFolderOptions, KSWindowHandle?) async -> URL?)? {
            get { lock.withLock { _onSelectFolder } }
            set { lock.withLock { _onSelectFolder = newValue } }
        }
        private var _onSelectFolder: ((KSSelectFolderOptions, KSWindowHandle?) async -> URL?)?

        public var onMessage: ((KSMessageOptions, KSWindowHandle?) async -> KSMessageResult)? {
            get { lock.withLock { _onMessage } }
            set { lock.withLock { _onMessage = newValue } }
        }
        private var _onMessage: ((KSMessageOptions, KSWindowHandle?) async -> KSMessageResult)?

        public init() {}

        // MARK: - KSDialogBackend

        public func openFile(
            options: KSOpenFileOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> [URL] {
            guard let handler = lock.withLock({ _onOpenFile }) else {
                throw KSError.unsupportedPlatform(
                    "KSiOSDialogBackend.openFile: UIKit bridge not installed")
            }
            return await handler(options, parent)
        }

        public func saveFile(
            options: KSSaveFileOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> URL? {
            guard let handler = lock.withLock({ _onSaveFile }) else {
                throw KSError.unsupportedPlatform(
                    "KSiOSDialogBackend.saveFile: UIKit bridge not installed")
            }
            return await handler(options, parent)
        }

        public func selectFolder(
            options: KSSelectFolderOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> URL? {
            guard let handler = lock.withLock({ _onSelectFolder }) else {
                throw KSError.unsupportedPlatform(
                    "KSiOSDialogBackend.selectFolder: UIKit bridge not installed")
            }
            return await handler(options, parent)
        }

        @discardableResult
        public func message(
            _ options: KSMessageOptions,
            parent: KSWindowHandle?
        ) async throws(KSError) -> KSMessageResult {
            guard let handler = lock.withLock({ _onMessage }) else {
                throw KSError.unsupportedPlatform(
                    "KSiOSDialogBackend.message: UIKit bridge not installed")
            }
            return await handler(options, parent)
        }
    }
#endif
