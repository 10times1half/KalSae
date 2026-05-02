#if os(Android)
    public import KalsaeCore

    /// `KSAutostartBackend`의 Android stub 구현체.
    ///
    /// 자동 시작(부팅 시 실행)은 Android 앱 모델에서 지원되지 않는다.
    /// iOS의 `KSiOSAutostartBackend`와 동일한 동작을 제공해
    /// 두 모바일 플랫폼이 대칭적인 PAL 표면을 갖도록 한다.
    public struct KSAndroidAutostartBackend: KSAutostartBackend, Sendable {
        public init() {}

        public func enable() throws(KSError) {
            throw KSError.unsupportedPlatform("Autostart is not available on Android")
        }

        public func disable() throws(KSError) {
            throw KSError.unsupportedPlatform("Autostart is not available on Android")
        }

        public func isEnabled() -> Bool {
            false
        }
    }
#endif
