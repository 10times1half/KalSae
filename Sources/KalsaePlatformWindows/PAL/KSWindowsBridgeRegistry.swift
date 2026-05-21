#if os(Windows)
    internal import KalsaeCore

    /// macOS의 `KSMacBridgeRegistry`에 대응하는 Windows 전용 브리지 레지스트리.
    ///
    /// `KSWindowsWindowBackend.create()`로 생성된 창마다 `WebView2Bridge`를
    /// 창 레이블과 함께 명시적으로 보관한다. 이 레지스트리가 없으면 브리지가
    /// `Win32Window.eventSink` 클로저 캡처에만 의존하게 되어, 외부에서
    /// `eventSink`를 교체하는 순간 IPC 연결이 끊어지는 문제를 방지한다.
    ///
    /// `@MainActor` 격리: `Win32App` / `Win32Window`와 동일한 스레드에서 동작.
    @MainActor
    internal final class KSWindowsBridgeRegistry {
        static let shared = KSWindowsBridgeRegistry()

        private init() {}

        private var byLabel: [String: WebView2Bridge] = [:]

        func register(label: String, bridge: WebView2Bridge) {
            byLabel[label] = bridge
        }

        func unregister(label: String) {
            byLabel.removeValue(forKey: label)
        }
    }
#endif
