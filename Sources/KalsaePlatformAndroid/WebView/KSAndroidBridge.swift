#if os(Android)
    public import KalsaeCore
    public import Foundation

    /// Bridges a `KSAndroidWebViewHost` to the Kalsae IPC core.
    ///
    /// Mirrors `KSiOSBridge` from the iOS platform — thin wrapper over
    /// `KSIPCBridgeCore`. Android's main thread is the Activity UI thread;
    /// Swift's `MainActor` maps to a Dispatch main queue hop.
    @MainActor
    public final class KSAndroidBridge {
        private let host: KSAndroidWebViewHost
        private let core: KSIPCBridgeCore
        internal let windowLabel: String

        public var onEvent: (@MainActor (String, Data?) -> Void)? {
            get { core.onEvent }
            set { core.onEvent = newValue }
        }

        public init(host: KSAndroidWebViewHost, registry: KSCommandRegistry, windowLabel: String) {
            self.host = host
            self.windowLabel = windowLabel
            self.core = KSIPCBridgeCore(
                registry: registry,
                windowLabel: windowLabel,
                logLabel: "platform.android.ipc.\(windowLabel)",
                post: { [weak host] json throws(KSError) in
                    try host?.postJSON(json)
                },
                hop: { block in
                    Task { @MainActor in block() }
                })
            // origin 해석기: 마지막 navigate URL을 정책 평가기에 전달.
            self.core.originResolver = { [weak host] in
                guard let s = host?.lastNavigatedURL else { return nil }
                return KSOrigin.string(fromString: s)
            }
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

        public func emit(event name: String, payload: any Encodable) throws(KSError) {
            try core.emit(event: name, payload: payload)
        }
    }
#endif
