#if os(Windows)
    internal import KalsaeCore

    /// macOS의 `KSMacBridgeRegistry`에 대칭하는 Windows 전용 레지스트리.
    ///
    /// `KSWindowsWindowBackend.create()`로 생성된 창의 `WebView2Bridge`를
    /// 창 레이블에 대응시켜 명시적으로 보유한다. 이 배열이 없으면 브리지가
    /// `Win32Window.eventSink` 클로저 캡처에만 의존하게 되어, 외부에서
    /// `eventSink`를 교체하는 순간 IPC 연결이 즉시 끊어진다.
    ///
    /// `@MainActor` 격리: `Win32App` / `Win32Window` 와 동일한 스레드.
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
