#if os(Android)
    public import KalsaeCore

    /// `KSMenuBackend`의 Android no-op 구현체.
    ///
    /// Android의 단일 Activity 모델에서는 앱 메뉴, 창별 메뉴, 컨텍스트 메뉴가
    /// 모두 적용되지 않으므로 조용히(no-op) 처리한다.
    /// iOS의 `KSiOSMenuBackend`와 동일한 동작으로 두 플랫폼이 대칭적인
    /// PAL 표면을 갖도록 한다.
    public struct KSAndroidMenuBackend: KSMenuBackend, Sendable {
        public init() {}

        public func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) {
            _ = items
        }

        public func installWindowMenu(
            _ handle: KSWindowHandle,
            items: [KSMenuItem]
        ) async throws(KSError) {
            _ = (handle, items)
        }

        public func showContextMenu(
            _ items: [KSMenuItem],
            at point: KSPoint,
            in handle: KSWindowHandle?
        ) async throws(KSError) {
            _ = (items, point, handle)
        }
    }
#endif
