#if os(iOS)
    public import KalsaeCore

    /// iOS는 macOS식 영구 메뉴바가 없고, 메뉴 시스템은 `UIMenuBuilder`를 통한
    /// 키보드 단축키 메뉴(주로 iPad)나 에딧 메뉴 형태로만 존재한다. 데스크톱
    /// 메뉴 모델과 직접 매핑되지 않으므로 v0.x에서는 명확한
    /// `unsupportedPlatform`로 거부한다. (RFC-004 §4 결정사항)
    public struct KSiOSMenuBackend: KSMenuBackend, Sendable {
        public init() {}

        public func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) {
            _ = items
            throw KSError.unsupportedPlatform(
                "iOS does not support a persistent application menu bar; "
                    + "use UIMenuBuilder integration in a future Kalsae phase.")
        }

        public func installWindowMenu(
            _ handle: KSWindowHandle,
            items: [KSMenuItem]
        ) async throws(KSError) {
            _ = (handle, items)
            throw KSError.unsupportedPlatform(
                "iOS does not support per-window menus.")
        }

        public func showContextMenu(
            _ items: [KSMenuItem],
            at point: KSPoint,
            in handle: KSWindowHandle?
        ) async throws(KSError) {
            _ = (items, point, handle)
            throw KSError.unsupportedPlatform(
                "iOS context menus require UIContextMenuInteraction integration "
                    + "(deferred to a future Kalsae phase).")
        }
    }
#endif
