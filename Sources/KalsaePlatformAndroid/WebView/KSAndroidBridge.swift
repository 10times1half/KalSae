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

    public var onEvent: (@MainActor (String, Data?) -> Void)? {
        get { core.onEvent }
        set { core.onEvent = newValue }
    }

    public init(host: KSAndroidWebViewHost, registry: KSCommandRegistry) {
        self.host = host
        self.core = KSIPCBridgeCore(
            registry: registry,
            logLabel: "platform.android.ipc",
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
