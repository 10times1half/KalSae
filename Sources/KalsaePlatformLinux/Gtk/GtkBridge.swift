#if os(Linux)
internal import CKalsaeGtk
internal import Logging
public import KalsaeCore
public import Foundation

/// Bridges a `GtkWebViewHost` to `KSCommandRegistry`. Thin wrapper over
/// `KSIPCBridgeCore`; only the GTK-specific plumbing lives here.
@MainActor
public final class GtkBridge {
    private let host: GtkWebViewHost
    private let core: KSIPCBridgeCore

    public var onEvent: (@MainActor (String, Data?) -> Void)? {
        get { core.onEvent }
        set { core.onEvent = newValue }
    }

    public init(host: GtkWebViewHost, registry: KSCommandRegistry) {
        self.host = host
        self.core = KSIPCBridgeCore(
            registry: registry,
            logLabel: "platform.linux.ipc",
            post: { [weak host] json throws(KSError) in
                try host?.postJSON(json)
            },
            // GTK 메인 루프는 Swift MainActor 실행기와 통합되지 않으므로
            // `g_idle_add`로 명시적으로 UI 스레드에 복귀해야 한다.
            hop: { block in
                GtkMainQueue.post(block)
            })
    }

    public func install() throws(KSError) {
        try host.onMessage { [weak self] text in
            self?.core.handleInbound(text)
        }
    }

    public func emit(event name: String,
                     payload: any Encodable) throws(KSError) {
        try core.emit(event: name, payload: payload)
    }
}

/// UI-thread dispatch helper used by `GtkBridge` (and exported via
/// `KSLinuxDemoHost.postJob`). Schedules `block` onto the GTK main
/// loop's idle queue.
internal enum GtkMainQueue {
    /// Schedules `block` on the GTK main thread. Safe to call from any thread.
    static func post(_ block: @escaping @MainActor () -> Void) {
        // 클로저를 힙 상의 박스에 담아 C 트램폴린에게 포인터를 넘긴다.
        // 이 박스는 트램폴린이 `block()` 실행을 끝낸 뒤 해제한다.
        let box = JobBox(block: block)
        let raw = Unmanaged.passRetained(box).toOpaque()
        ks_gtk_post_main_thread(gtkMainQueueTrampoline, raw)
    }
}

private final class JobBox: @unchecked Sendable {
    let block: @MainActor () -> Void
    init(block: @escaping @MainActor () -> Void) { self.block = block }
}

private let gtkMainQueueTrampoline: @convention(c) (
    UnsafeMutableRawPointer?
) -> Void = { raw in
    guard let raw else { return }
    let box = Unmanaged<JobBox>.fromOpaque(raw).takeRetainedValue()
    MainActor.assumeIsolated { box.block() }
}

extension GtkWebViewHost {
    /// Posts a closure onto the GTK main thread. Safe to call from any
    /// thread (wraps `g_idle_add`).
    nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
        GtkMainQueue.post(block)
    }
}
#endif
