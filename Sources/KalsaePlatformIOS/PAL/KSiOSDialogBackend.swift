#if os(iOS)
    public import KalsaeCore
    public import Foundation
    internal import UIKit
    internal import UniformTypeIdentifiers

    /// `KSDialogBackend`의 iOS 구현체.
    ///
    /// `init()` 단계에서 UIKit 기반 기본 핸들러(`UIAlertController` /
    /// `UIDocumentPickerViewController`)가 자동 설치되므로 호스트가 추가 설정
    /// 없이 `__ks.dialog.*` 명령을 사용할 수 있다. 호스트가 도메인 특화 로직을
    /// 원하면 `onOpenFile` / `onSaveFile` / `onSelectFolder` / `onMessage` 슬롯에
    /// 자체 핸들러를 할당해 덮어쓸 수 있다.
    ///
    /// iOS 16+ 에서 동작하며, 부모 뷰 컨트롤러는 `KSiOSHandleRegistry`에 등록된
    /// `UIWindow.rootViewController`를 우선 사용하고 그 외에는 `connectedScenes`의
    /// keyWindow rootViewController로 폴백한다.
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

        public init() {
            // 기본 UIKit 핸들러 자동 설치. 호스트가 슬롯에 다른 핸들러를
            // 할당하면 자동으로 덮어쓰여진다 (NSLock으로 보호된 setter).
            self._onOpenFile = { opts, parent in
                await KSiOSDialogPresenter.openFile(options: opts, parent: parent)
            }
            self._onSaveFile = { opts, parent in
                await KSiOSDialogPresenter.saveFile(options: opts, parent: parent)
            }
            self._onSelectFolder = { opts, parent in
                await KSiOSDialogPresenter.selectFolder(options: opts, parent: parent)
            }
            self._onMessage = { opts, parent in
                await KSiOSDialogPresenter.message(options: opts, parent: parent)
            }
        }

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

    // MARK: - 기본 UIKit 핸들러

    /// `KSiOSDialogBackend.init()`이 사용하는 UIKit 기반 기본 다이얼로그 프레젠터.
    /// 모든 메서드는 메인 액터에서 실행되며, `UIDocumentPickerViewController` /
    /// `UIAlertController`를 부모 뷰 컨트롤러 위에 모달로 띄운다.
    @MainActor
    internal enum KSiOSDialogPresenter {

        /// 등록된 윈도우의 rootViewController, 없으면 활성 씬의 keyWindow rootVC.
        static func parentVC(for handle: KSWindowHandle?) -> UIViewController? {
            if let label = handle?.label,
                let win = KSiOSHandleRegistry.shared.window(for: label),
                let rootVC = win.rootViewController
            {
                return topMost(rootVC)
            }
            for scene in UIApplication.shared.connectedScenes {
                if let ws = scene as? UIWindowScene,
                    let key = ws.windows.first(where: { $0.isKeyWindow }) ?? ws.windows.first,
                    let rootVC = key.rootViewController
                {
                    return topMost(rootVC)
                }
            }
            return nil
        }

        private static func topMost(_ vc: UIViewController) -> UIViewController {
            if let presented = vc.presentedViewController {
                return topMost(presented)
            }
            return vc
        }

        // MARK: openFile

        static func openFile(
            options: KSOpenFileOptions, parent: KSWindowHandle?
        ) async -> [URL] {
            guard let host = parentVC(for: parent) else {
                KSLog.logger("platform.ios.dialog").warning(
                    "openFile: no parent UIViewController; returning [].")
                return []
            }
            let types = utTypes(forFilters: options.filters, fallback: [.item])
            return await withCheckedContinuation { (cont: CheckedContinuation<[URL], Never>) in
                let picker = UIDocumentPickerViewController(
                    forOpeningContentTypes: types,
                    asCopy: true)
                picker.allowsMultipleSelection = options.allowsMultiple
                if let dir = options.defaultDirectory {
                    picker.directoryURL = dir
                }
                let proxy = KSiOSDocumentPickerProxy(
                    onPick: { urls in cont.resume(returning: urls) },
                    onCancel: { cont.resume(returning: []) })
                picker.delegate = proxy
                picker.ks_retainProxy = proxy
                host.present(picker, animated: true)
            }
        }

        // MARK: saveFile

        static func saveFile(
            options: KSSaveFileOptions, parent: KSWindowHandle?
        ) async -> URL? {
            guard let host = parentVC(for: parent) else {
                KSLog.logger("platform.ios.dialog").warning(
                    "saveFile: no parent UIViewController; returning nil.")
                return nil
            }
            // iOS는 데스크톱식 "save destination" picker가 없다. 표준 패턴은
            // 빈 임시 파일을 만든 뒤 export picker로 사용자가 위치를 고르게
            // 하는 것이다. 사용자가 직접 데이터를 쓰려면 반환된 URL을 사용.
            let suggested = options.defaultFileName ?? "Untitled.txt"
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(suggested)
            do {
                if !FileManager.default.fileExists(atPath: tmp.path) {
                    FileManager.default.createFile(atPath: tmp.path, contents: Data())
                }
            }
            return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
                let picker = UIDocumentPickerViewController(
                    forExporting: [tmp], asCopy: true)
                if let dir = options.defaultDirectory {
                    picker.directoryURL = dir
                }
                let proxy = KSiOSDocumentPickerProxy(
                    onPick: { urls in cont.resume(returning: urls.first) },
                    onCancel: { cont.resume(returning: nil) })
                picker.delegate = proxy
                picker.ks_retainProxy = proxy
                host.present(picker, animated: true)
            }
        }

        // MARK: selectFolder

        static func selectFolder(
            options: KSSelectFolderOptions, parent: KSWindowHandle?
        ) async -> URL? {
            guard let host = parentVC(for: parent) else {
                KSLog.logger("platform.ios.dialog").warning(
                    "selectFolder: no parent UIViewController; returning nil.")
                return nil
            }
            return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
                let picker = UIDocumentPickerViewController(
                    forOpeningContentTypes: [.folder],
                    asCopy: false)
                if let dir = options.defaultDirectory {
                    picker.directoryURL = dir
                }
                let proxy = KSiOSDocumentPickerProxy(
                    onPick: { urls in cont.resume(returning: urls.first) },
                    onCancel: { cont.resume(returning: nil) })
                picker.delegate = proxy
                picker.ks_retainProxy = proxy
                host.present(picker, animated: true)
            }
        }

        // MARK: message

        static func message(
            options: KSMessageOptions, parent: KSWindowHandle?
        ) async -> KSMessageResult {
            guard let host = parentVC(for: parent) else {
                KSLog.logger("platform.ios.dialog").warning(
                    "message: no parent UIViewController; returning .cancel.")
                return .cancel
            }
            return await withCheckedContinuation { (cont: CheckedContinuation<KSMessageResult, Never>) in
                let alert = UIAlertController(
                    title: options.title.isEmpty ? nil : options.title,
                    message: options.detail.map { "\(options.message)\n\n\($0)" }
                        ?? options.message,
                    preferredStyle: .alert)
                let style: UIAlertAction.Style = (options.kind == .error) ? .destructive : .default
                switch options.buttons {
                case .ok:
                    alert.addAction(UIAlertAction(title: "OK", style: style) { _ in
                        cont.resume(returning: .ok)
                    })
                case .okCancel:
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                        cont.resume(returning: .cancel)
                    })
                    alert.addAction(UIAlertAction(title: "OK", style: style) { _ in
                        cont.resume(returning: .ok)
                    })
                case .yesNo:
                    alert.addAction(UIAlertAction(title: "No", style: .cancel) { _ in
                        cont.resume(returning: .no)
                    })
                    alert.addAction(UIAlertAction(title: "Yes", style: style) { _ in
                        cont.resume(returning: .yes)
                    })
                case .yesNoCancel:
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                        cont.resume(returning: .cancel)
                    })
                    alert.addAction(UIAlertAction(title: "No", style: .default) { _ in
                        cont.resume(returning: .no)
                    })
                    alert.addAction(UIAlertAction(title: "Yes", style: style) { _ in
                        cont.resume(returning: .yes)
                    })
                }
                host.present(alert, animated: true)
            }
        }

        // MARK: utility

        private static func utTypes(
            forFilters filters: [KSFileFilter], fallback: [UTType]
        ) -> [UTType] {
            var out: [UTType] = []
            for f in filters {
                for ext in f.extensions {
                    if let t = UTType(filenameExtension: ext) {
                        out.append(t)
                    }
                }
            }
            return out.isEmpty ? fallback : out
        }
    }

    /// `UIDocumentPickerDelegate` 프록시 — picker가 dismiss 될 때까지 살아있도록
    /// `picker.ks_retainProxy` (associated object)에 보관한다.
    @MainActor
    internal final class KSiOSDocumentPickerProxy: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        private let onCancel: () -> Void
        private var fired = false

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard !fired else { return }
            fired = true
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !fired else { return }
            fired = true
            onCancel()
        }
    }

    private nonisolated(unsafe) var ksiOSPickerProxyKey: UInt8 = 0

    extension UIDocumentPickerViewController {
        /// picker 표시 동안 delegate 프록시의 lifetime을 보장한다.
        @MainActor
        fileprivate var ks_retainProxy: KSiOSDocumentPickerProxy? {
            get {
                objc_getAssociatedObject(self, &ksiOSPickerProxyKey)
                    as? KSiOSDocumentPickerProxy
            }
            set {
                objc_setAssociatedObject(
                    self, &ksiOSPickerProxyKey, newValue,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
#endif
