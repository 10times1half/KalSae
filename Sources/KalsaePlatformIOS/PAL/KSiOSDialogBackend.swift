#if os(iOS)
    public import KalsaeCore
    public import Foundation
    internal import UIKit
    internal import UniformTypeIdentifiers

    /// `KSDialogBackend`의 iOS 구현체입니다.
    ///
    /// `init()` 단계에서 UIKit 기반 기본 핸들러(`UIAlertController` /
    /// `UIDocumentPickerViewController`)가 자동 설치되므로, 호스트가 추가
    /// 설정 없이 `__ks.dialog.*` 명령을 사용할 수 있습니다. 호스트가 도메인
    /// 특화 로직을 원하면 `onOpenFile` / `onSaveFile` / `onSelectFolder` /
    /// `onMessage` 슬롯에 자체 핸들러를 할당해 덮어쓸 수 있습니다.
    ///
    /// iOS 16+에서 동작하며, 부모 뷰 컨트롤러는 `KSiOSHandleRegistry`에
    /// 등록된 `UIWindow.rootViewController`를 우선 사용하고, 등록된 윈도우가
    /// 없으면 `connectedScenes`의 keyWindow rootViewController로 폴백합니다.
    ///
    /// - Note: `@unchecked Sendable`을 사용하는 이유는 `NSLock`으로 상태를
    ///   보호하면서도 UIKit의 메인 스레드 어피니티가 있기 때문입니다. 액터는
    ///   정적 공유 인스턴스의 UI 관련 동기 접근에 적합하지 않습니다.
    // @unchecked: NSLock + UIKit 메인 스레드 어피니티 — actor 부적합
    public final class KSiOSDialogBackend: KSDialogBackend, @unchecked Sendable {
        private let lock = NSLock()

        // MARK: - 주입 가능한 핸들러 (UIKit 호스트가 설정)

        /// 파일 열기 핸들러입니다. UIKit 호스트가 자체 구현으로 교체할 수 있습니다.
        /// - Parameters:
        ///   - options: 파일 열기 옵션 (다중 선택, 필터 등)
        ///   - KSWindowHandle?: 부모 윈도우 핸들 (선택 사항)
        /// - Returns: 사용자가 선택한 파일 URL 배열
        public var onOpenFile: ((KSOpenFileOptions, KSWindowHandle?) async -> [URL])? {
            get { lock.withLock { _onOpenFile } }
            set { lock.withLock { _onOpenFile = newValue } }
        }
        private var _onOpenFile: ((KSOpenFileOptions, KSWindowHandle?) async -> [URL])?

        /// 파일 저장 핸들러입니다. UIKit 호스트가 자체 구현으로 교체할 수 있습니다.
        public var onSaveFile: ((KSSaveFileOptions, KSWindowHandle?) async -> URL?)? {
            get { lock.withLock { _onSaveFile } }
            set { lock.withLock { _onSaveFile = newValue } }
        }
        private var _onSaveFile: ((KSSaveFileOptions, KSWindowHandle?) async -> URL?)?

        /// 폴더 선택 핸들러입니다. UIKit 호스트가 자체 구현으로 교체할 수 있습니다.
        public var onSelectFolder: ((KSSelectFolderOptions, KSWindowHandle?) async -> URL?)? {
            get { lock.withLock { _onSelectFolder } }
            set { lock.withLock { _onSelectFolder = newValue } }
        }
        private var _onSelectFolder: ((KSSelectFolderOptions, KSWindowHandle?) async -> URL?)?

        /// 메시지/알림 다이얼로그 핸들러입니다. UIKit 호스트가 자체 구현으로 교체할 수 있습니다.
        public var onMessage: ((KSMessageOptions, KSWindowHandle?) async -> KSMessageResult)? {
            get { lock.withLock { _onMessage } }
            set { lock.withLock { _onMessage = newValue } }
        }
        private var _onMessage: ((KSMessageOptions, KSWindowHandle?) async -> KSMessageResult)?

        public init() {
            // 기본 UIKit 핸들러 자동 설치. 호스트가 슬롯에 다른 핸들러를
            // 할당하면 NSLock으로 보호된 setter를 통해 자동으로 덮어쓰여집니다.
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

        // MARK: - KSDialogBackend 프로토콜 구현

        /// 파일 열기 다이얼로그를 표시합니다.
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

        /// 파일 저장 다이얼로그를 표시합니다.
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

        /// 폴더 선택 다이얼로그를 표시합니다.
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

        /// 메시지 다이얼로그(알림/확인/경고)를 표시합니다.
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

    // MARK: - 기본 UIKit 다이얼로그 프레젠터

    /// `KSiOSDialogBackend.init()`이 사용하는 UIKit 기반 기본 다이얼로그 프레젠터입니다.
    /// 모든 메서드는 메인 액터에서 실행되며, `UIDocumentPickerViewController` /
    /// `UIAlertController`를 부모 뷰 컨트롤러 위에 모달로 표시합니다.
    @MainActor
    internal enum KSiOSDialogPresenter {

        /// 등록된 윈도우의 rootViewController를 반환합니다.
        /// `handle`에 해당하는 윈도우가 있으면 그 rootViewController를,
        /// 없으면 활성 씬의 keyWindow rootViewController로 폴백합니다.
        /// - Parameter handle: 대상 윈도우 핸들 (선택 사항)
        /// - Returns: 최상위 UIViewController (찾을 수 없으면 `nil`)
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

        /// 가장 위에 표시된 뷰 컨트롤러를 재귀적으로 찾습니다.
        /// - Parameter vc: 시작점 뷰 컨트롤러
        /// - Returns: 최상위 presentedViewController
        private static func topMost(_ vc: UIViewController) -> UIViewController {
            if let presented = vc.presentedViewController {
                return topMost(presented)
            }
            return vc
        }

        // MARK: 파일 열기 (openFile)

        /// `UIDocumentPickerViewController`를 사용하여 파일 열기 다이얼로그를 표시합니다.
        /// 선택된 파일은 복사본(asCopy: true)으로 제공됩니다.
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

        // MARK: 파일 저장 (saveFile)

        /// iOS는 데스크톱식 "저장 위치 선택" 피커가 없으므로, 빈 임시 파일을
        /// 만든 뒤 `UIDocumentPickerViewController(forExporting:)`로 사용자가
        /// 저장 위치를 고르게 합니다.
        static func saveFile(
            options: KSSaveFileOptions, parent: KSWindowHandle?
        ) async -> URL? {
            guard let host = parentVC(for: parent) else {
                KSLog.logger("platform.ios.dialog").warning(
                    "saveFile: no parent UIViewController; returning nil.")
                return nil
            }
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

        // MARK: 폴더 선택 (selectFolder)

        /// `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])`를
        /// 사용하여 폴더 선택 다이얼로그를 표시합니다.
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

        // MARK: 메시지 다이얼로그 (message)

        /// `UIAlertController`를 사용하여 메시지 다이얼로그(알림/확인/경고)를
        /// 표시합니다. 버튼 구성(`.ok`, `.okCancel`, `.yesNo`, `.yesNoCancel`)에
        /// 따라 적절한 버튼을 배치합니다.
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
                    alert.addAction(
                        UIAlertAction(title: "OK", style: style) { _ in
                            cont.resume(returning: .ok)
                        })
                case .okCancel:
                    alert.addAction(
                        UIAlertAction(title: "Cancel", style: .cancel) { _ in
                            cont.resume(returning: .cancel)
                        })
                    alert.addAction(
                        UIAlertAction(title: "OK", style: style) { _ in
                            cont.resume(returning: .ok)
                        })
                case .yesNo:
                    alert.addAction(
                        UIAlertAction(title: "No", style: .cancel) { _ in
                            cont.resume(returning: .no)
                        })
                    alert.addAction(
                        UIAlertAction(title: "Yes", style: style) { _ in
                            cont.resume(returning: .yes)
                        })
                case .yesNoCancel:
                    alert.addAction(
                        UIAlertAction(title: "Cancel", style: .cancel) { _ in
                            cont.resume(returning: .cancel)
                        })
                    alert.addAction(
                        UIAlertAction(title: "No", style: .default) { _ in
                            cont.resume(returning: .no)
                        })
                    alert.addAction(
                        UIAlertAction(title: "Yes", style: style) { _ in
                            cont.resume(returning: .yes)
                        })
                }
                host.present(alert, animated: true)
            }
        }

        // MARK: 유틸리티

        /// `KSFileFilter` 배열에서 `UTType` 배열로 변환합니다.
        /// 필터가 비어 있으면 fallback 값을 반환합니다.
        /// - Parameters:
        ///   - filters: 파일 필터 배열 (확장자 목록)
        ///   - fallback: 필터가 없을 때 사용할 기본 UTType
        /// - Returns: UTType 배열
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

    /// `UIDocumentPickerDelegate` 프록시 클래스입니다.
    /// picker가 dismiss 될 때까지 delegate 프록시의 lifetime을 보장하기 위해
    /// `picker.ks_retainProxy` (associated object)에 보관합니다.
    @MainActor
    internal final class KSiOSDocumentPickerProxy: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        private let onCancel: () -> Void
        private var fired = false

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        /// 사용자가 파일을 선택했을 때 호출됩니다.
        /// 중복 호출을 방지하기 위해 `fired` 플래그로 1회만 실행됩니다.
        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard !fired else { return }
            fired = true
            onPick(urls)
        }

        /// 사용자가 피커를 취소했을 때 호출됩니다.
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !fired else { return }
            fired = true
            onCancel()
        }
    }

    private nonisolated(unsafe) var ksiOSPickerProxyKey: UInt8 = 0

    extension UIDocumentPickerViewController {
        /// picker 표시 동안 delegate 프록시의 lifetime을 보장하기 위한
        /// associated object 저장소입니다.
        /// `objc_setAssociatedObject`의 `OBJC_ASSOCIATION_RETAIN_NONATOMIC`
        /// 정책으로 객체를 유지합니다.
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
