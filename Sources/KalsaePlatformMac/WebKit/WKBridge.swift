#if os(macOS)
    internal import Logging
    public import KalsaeCore
    public import Foundation

    /// `WKWebViewHost`를 Kalsae IPC 코어에 연결하는 브리지.
    ///
    /// `KSIPCBridgeCore`의 업은 래퍼: 실질적인 처리(와이어 디코드,
    /// 디스패치, 응답 인코드, 이벤트 이미트)는 KalsaeCore에 있어
    /// 플랫폼 간 동일하다. 이 타입은 `WKWebViewHost` 배관만 담당한다.
    @MainActor
    public final class WKBridge {
        private let host: WKWebViewHost
        private let core: KSIPCBridgeCore
        internal let windowLabel: String

        /// JS에서 수신하는 `emit` 메시지의 싱크.
        public var onEvent: (@MainActor (String, Data?) -> Void)? {
            get { core.onEvent }
            set { core.onEvent = newValue }
        }

        public init(host: WKWebViewHost, registry: KSCommandRegistry, windowLabel: String) {
            self.host = host
            self.windowLabel = windowLabel
            self.core = KSIPCBridgeCore(
                registry: registry,
                windowLabel: windowLabel,
                logLabel: "platform.mac.ipc.\(windowLabel)",
                post: { [weak host] json throws(KSError) in
                    try host?.postJSON(json)
                },
                // AppKit 런루프가 MainActor 실행기를 펌프하므로 일반 `Task`로 충분.
                hop: { block in
                    Task { @MainActor in block() }
                })
            KSWindowEmitHub.shared.register(label: windowLabel) { [weak self] event, payload throws(KSError) in
                guard let self else { return }
                try self.emit(event: event, payload: payload)
            }
        }

        public func install() throws(KSError) {
            try host.onMessage { [weak self] text in
                self?.core.handleInbound(text)
            }
        }

        /// JS로 이벤트를 발행한다 (`window.__KS_.listen(name, cb)`).
        public func emit(
            event name: String,
            payload: any Encodable
        ) throws(KSError) {
            try core.emit(event: name, payload: payload)
        }
    }
#endif
