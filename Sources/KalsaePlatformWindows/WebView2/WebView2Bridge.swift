#if os(Windows)
    internal import Logging
    public import KalsaeCore
    public import Foundation

    /// Bridges a `WebView2Host` to the Kalsae IPC core (`KSCommandRegistry`
    /// and cross-window events). Thin wrapper over `KSIPCBridgeCore`; only
    /// the WebView2-specific plumbing lives here.
    @MainActor
    public final class WebView2Bridge {
        private let host: WebView2Host
        private let core: KSIPCBridgeCore

        /// Sink for `emit` messages from JS. Subscribing here is the Swift
        /// side of `window.__KS_.listen`.
        public var onEvent: (@MainActor (_ name: String, _ payload: Data?) -> Void)? {
            get { core.onEvent }
            set { core.onEvent = newValue }
        }

        internal init(host: WebView2Host, registry: KSCommandRegistry) {
            self.host = host
            self.core = KSIPCBridgeCore(
                registry: registry,
                logLabel: "platform.windows.ipc",
                post: { [weak host] json throws(KSError) in
                    try host?.postJSON(json)
                },
                // Win32 메시지 루프는 Swift MainActor 실행기와 통합되지 않으므로
                // PostMessageW(WM_KS_JOB)로 명시적으로 UI 스레드에 복귀한다.
                hop: { [weak host] block in
                    host?.postJob(block)
                })
        }

        internal func install() throws(KSError) {
            try host.onMessage { [weak self] text in
                self?.core.handleInbound(text)
            }
        }

        /// Emits an event to JS (`window.__KS_.listen(name, cb)`).
        public func emit(
            event name: String,
            payload: any Encodable
        ) throws(KSError) {
            try core.emit(event: name, payload: payload)
        }
    }
#endif
