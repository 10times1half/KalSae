#if os(iOS)
    public import KalsaeCore

    /// iOS에서 메뉴(및 향후 트레이) 명령 활성화를 구독자에게 라우팅합니다.
    ///
    /// `KSMacCommandRouter` / `KSWindowsCommandRouter` / `KSLinuxCommandRouter` /
    /// `KSAndroidCommandRouter`와 동일한 형태를 가지므로, 플랫폼별 메뉴
    /// 백엔드가 모두 동일한 라우팅 인터페이스로 명령을 방출할 수 있습니다.
    ///
    /// 구독자는 일반적으로 `KSApp`에서 연결되므로, 메뉴 활성화가 IPC
    /// `__ks.command(...)` 호출과 동일한 핸들러에 도달하게 됩니다.
    /// 즉, 사용자가 네이티브 메뉴 항목을 클릭하거나 JS에서 `__ks.command()`를
    /// 호출하더라도 동일한 커맨드 처리 로직이 실행됩니다.
    ///
    /// - Note: `@MainActor`로 보호되므로, 모든 구독/디스패치는 메인 스레드에서
    ///   이루어져야 합니다. UIKit의 UI 업데이트와의 경합을 방지합니다.
    @MainActor
    public final class KSiOSCommandRouter: KSMenuCommandRouting {
        /// 전역 싱글톤 인스턴스입니다.
        public static let shared = KSiOSCommandRouter()

        /// 명령어와 선택적 항목 ID를 받아 처리하는 클로저 타입입니다.
        /// - Parameters:
        ///   - command: 실행할 명령어 문자열 (예: `"app.quit"`)
        ///   - itemID: 메뉴 항목의 고유 식별자 (선택 사항)
        public typealias Sink = @MainActor (_ command: String, _ itemID: String?) -> Void
        private var sinks: [Sink] = []

        private init() {}

        /// 명령어를 수신할 구독자를 등록합니다.
        /// - Parameter sink: 명령어가 디스패치될 때 호출될 클로저
        public func subscribe(_ sink: @escaping Sink) { sinks.append(sink) }

        /// 등록된 모든 구독자를 제거합니다.
        public func clear() { sinks.removeAll() }

        /// 등록된 모든 구독자에게 명령어를 전파합니다.
        /// - Parameters:
        ///   - command: 실행할 명령어 문자열
        ///   - itemID: 메뉴 항목의 고유 식별자 (선택 사항)
        internal func dispatch(command: String, itemID: String?) {
            for sink in sinks { sink(command, itemID) }
        }
    }
#endif
