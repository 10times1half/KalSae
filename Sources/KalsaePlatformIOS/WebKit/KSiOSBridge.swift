#if os(iOS)
    public import KalsaeCore
    public import Foundation

    /// `KSiOSWebViewHost`를 Kalsae IPC 코어에 연결하는 브리지.
    ///
    /// macOS 플랫폼의 `WKBridge`를 미러링 — `KSIPCBridgeCore`의 업은 래퍼.
    /// UIKit 런 루프가 `MainActor` 실행기를 펀프하므로 평범한 `Task { @MainActor }` 홈으로 충분하다.
    @MainActor
    public final class KSiOSBridge {
        private let host: KSiOSWebViewHost
        private let core: KSIPCBridgeCore

        public var onEvent: (@MainActor (String, Data?) -> Void)? {
            get { core.onEvent }
            set { core.onEvent = newValue }
        }

        public init(host: KSiOSWebViewHost, registry: KSCommandRegistry) {
            self.host = host
            self.core = KSIPCBridgeCore(
                registry: registry,
                logLabel: "platform.ios.ipc",
                post: { [weak host] json throws(KSError) in
                    try host?.postJSON(json)
                },
                hop: { block in
                    Task { @MainActor in block() }
                })
        }

        public func install() throws(KSError) {
            try host.onMessage { [weak self] text in
                self?.core.handleInbound(text)
            }
        }

        public func emit(event name: String, payload: any Encodable) throws(KSError) {
            try core.emit(event: name, payload: payload)
        }
    }
#endif
