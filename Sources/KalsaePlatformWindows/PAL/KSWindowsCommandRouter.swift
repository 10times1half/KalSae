#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore
    internal import Foundation

    /// 메뉴 / 트레이 명령을 구독자(subscriber)로 라우팅한다. 플랫폼 계층
    /// (또는 데모)이 단일 sink를 설치해 JS 브리지, 명령 레지스트리, 또는
    /// 둘 다로 전달한다.
    @MainActor
    public final class KSWindowsCommandRouter {
        public static let shared = KSWindowsCommandRouter()

        public typealias Sink = @MainActor (_ command: String, _ itemID: String?) -> Void
        private var sinks: [Sink] = []

        private init() {}

        /// 명령 구독자를 추가한다. `KSMenuItem.command`가 `nil`이 아닌 모든
        /// 메뉴 / 트레이 클릭마다 호출된다.
        public func subscribe(_ sink: @escaping Sink) {
            sinks.append(sink)
        }

        public func clear() {
            sinks.removeAll()
        }

        internal func dispatch(command: String, itemID: String?) {
            for sink in sinks { sink(command, itemID) }
        }
    }
#endif
