#if os(macOS)
internal import Logging
public import KalsaeCore
public import Foundation

/// Bridges a `WKWebViewHost` to the Kalsae IPC core.
///
/// Thin wrapper over `KSIPCBridgeCore`: the heavy lifting (wire decode,
/// dispatch, response encode, event emit) lives in KalsaeCore, identical
/// across platforms. This type only owns the `WKWebViewHost` plumbing.
@MainActor
public final class WKBridge {
    private let host: WKWebViewHost
    private let core: KSIPCBridgeCore

    /// Sink for `emit` messages from JS.
    public var onEvent: (@MainActor (String, Data?) -> Void)? {
        get { core.onEvent }
        set { core.onEvent = newValue }
    }

    public init(host: WKWebViewHost, registry: KSCommandRegistry) {
        self.host = host
        self.core = KSIPCBridgeCore(
            registry: registry,
            logLabel: "platform.mac.ipc",
            post: { [weak host] json throws(KSError) in
                try host?.postJSON(json)
            },
            // AppKit 런루프가 MainActor 실행기를 펌프하므로 일반 `Task`로 충분.
            hop: { block in
                Task { @MainActor in block() }
            })
    }

    public func install() throws(KSError) {
        try host.onMessage { [weak self] text in
            self?.core.handleInbound(text)
        }
    }

    /// Emits an event to JS (`window.__KS_.listen(name, cb)`).
    public func emit(event name: String,
                     payload: any Encodable) throws(KSError) {
        try core.emit(event: name, payload: payload)
    }
}
#endif
