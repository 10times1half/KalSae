#if os(iOS)
    public import KalsaeCore

    /// iOS용 자동 시작(Autostart) 백엔드 구현체입니다.
    ///
    /// iOS는 앱 수명 주기를 전적으로 운영체제가 관리하므로, 데스크톱 OS
    /// (Windows/macOS/Linux)와 같은 의미의 '시스템 부팅 시 앱 자동 실행' 기능을
    /// 제공하지 않습니다. iOS에서 앱이 실행되는 유일한 방법은 사용자가
    /// 홈 화면의 앱 아이콘을 직접 탭하거나, 시스템이 특정 이벤트(푸시 알림,
    /// 백그라운드 페치, URL 핸들링 등)에 응답하여 앱을 다시 실행하는 것입니다.
    ///
    /// 따라서 이 백엔드의 모든 메서드는 단순히 `.unsupportedPlatform` 오류를
    /// 던지거나 `false`를 반환합니다. 이는 `KSAutostartBackend` 프로토콜을
    /// 준수해야 하는 컴파일 요구사항을 충족하면서, iOS에서 이 기능이
    /// 작동하지 않음을 명확히 알리기 위함입니다.
    ///
    /// - Note: iOS 14 이후의 `BGTaskScheduler`를 사용한 백그라운드 작업 예약은
    ///   '자동 시작'이 아니라 '시스템이 허용하는 백그라운드 작업'이므로 이와
    ///   별개의 개념입니다.
    public struct KSiOSAutostartBackend: KSAutostartBackend, Sendable {
        public init() {}

        /// 자동 시작을 활성화합니다.
        /// iOS에서는 지원하지 않으므로 항상 `.unsupportedPlatform` 오류를 던집니다.
        /// - Throws: `KSError` — 항상 `code: .unsupportedPlatform`
        public func enable() throws(KSError) {
            throw KSError.unsupportedPlatform("Autostart is not available on iOS")
        }

        /// 자동 시작을 비활성화합니다.
        /// iOS에서는 지원하지 않으므로 항상 `.unsupportedPlatform` 오류를 던집니다.
        /// - Throws: `KSError` — 항상 `code: .unsupportedPlatform`
        public func disable() throws(KSError) {
            throw KSError.unsupportedPlatform("Autostart is not available on iOS")
        }

        /// 자동 시작이 활성화되어 있는지 여부를 반환합니다.
        /// iOS에서는 이 기능을 지원하지 않으므로 항상 `false`를 반환합니다.
        /// - Returns: 항상 `false`
        public func isEnabled() -> Bool {
            false
        }
    }
#endif
