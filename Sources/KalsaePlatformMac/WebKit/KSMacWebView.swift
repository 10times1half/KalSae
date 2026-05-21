#if os(macOS)
    internal import AppKit
    internal import WebKit

    /// `WKWebView` 서브클래스 — RFC-008 §2.2 외부 파일 드롭 이미터를 위해
    /// `NSDraggingDestination` 메서드를 가로채는 후크 지점.
    ///
    /// `fileDropHandler`가 nil이면 super(WKWebView 기본 동작 = WebCore로 위임 →
    /// HTML5 `drop` 이벤트)로 통과한다. nil이 아니고 드래그 페이스트보드에
    /// 파일 URL이 포함되어 있으면 super를 호출하지 않고 핸들러를 직접 호출해
    /// 네이티브 측에서 `__ks.file.drop` 이벤트로 emit한다.
    ///
    /// 일반적으로 `setAllowExternalDrop(false)`와 함께 사용된다 — JS 측에서는
    /// preventDefault해 HTML5 drop 이벤트를 무력화하고, 네이티브 이미터가
    /// 단일 진실의 원천이 된다.
    @MainActor
    internal final class KSMacWebView: WKWebView {
        /// drag 이벤트 핸들러. 반환값은 `performDragOperation`에서만 사용 —
        /// true이면 drop을 수락. `enter`/`leave`/`update` 반환값은 무시된다.
        var fileDropHandler: ((String, NSPoint, [String]) -> Bool)?

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            if let handler = fileDropHandler {
                let paths = Self.extractFilePaths(sender)
                if !paths.isEmpty {
                    _ = handler("enter", sender.draggingLocation, paths)
                    return .copy
                }
            }
            return super.draggingEntered(sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            if fileDropHandler != nil {
                let paths = Self.extractFilePaths(sender)
                if !paths.isEmpty {
                    return .copy
                }
            }
            return super.draggingUpdated(sender)
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            if let handler = fileDropHandler, let sender, !Self.extractFilePaths(sender).isEmpty {
                _ = handler("leave", sender.draggingLocation, [])
            }
            super.draggingExited(sender)
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            if let handler = fileDropHandler {
                let paths = Self.extractFilePaths(sender)
                if !paths.isEmpty {
                    return handler("drop", sender.draggingLocation, paths)
                }
            }
            return super.performDragOperation(sender)
        }

        private static func extractFilePaths(_ sender: any NSDraggingInfo) -> [String] {
            let pb = sender.draggingPasteboard
            guard
                let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
            else {
                return []
            }
            var paths: [String] = []
            paths.reserveCapacity(urls.count)
            for url in urls where url.isFileURL {
                paths.append(url.path)
            }
            return paths
        }
    }
#endif
