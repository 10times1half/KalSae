#if os(Linux)
    internal import CKalsaeGtk
    internal import Logging
    public import KalsaeCore
    public import Foundation

    /// `GtkWebViewHost`를 `KSCommandRegistry`에 연결하는 브리지.
    /// GTK 전용 배관만 여기에 있는 `KSIPCBridgeCore`의 업은 래퍼.
    @MainActor
    public final class GtkBridge {
        private let host: GtkWebViewHost
        private let core: KSIPCBridgeCore
        internal let windowLabel: String

        public var onEvent: (@MainActor (String, Data?) -> Void)? {
            get { core.onEvent }
            set { core.onEvent = newValue }
        }

        public init(host: GtkWebViewHost, registry: KSCommandRegistry, windowLabel: String) {
            self.host = host
            self.windowLabel = windowLabel
            self.core = KSIPCBridgeCore(
                registry: registry,
                windowLabel: windowLabel,
                logLabel: "platform.linux.ipc.\(windowLabel)",
                post: { [weak host] json throws(KSError) in
                    try host?.postJSON(json)
                },
                // GTK 메인 루프는 Swift MainActor 실행기와 통합되지 않으므로
                // `g_idle_add`로 명시적으로 UI 스레드에 복귀해야 한다.
                hop: { block in
                    GtkMainQueue.post(block)
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

        public func emit(
            event name: String,
            payload: any Encodable
        ) throws(KSError) {
            try core.emit(event: name, payload: payload)
        }
    }

    /// `GtkBridge` (및 `KSLinuxDemoHost.postJob`를 통해 노출)가 사용하는
    /// UI 스레드 디스패치 헬퍼. GTK 메인 루프의 idle 큐에
    /// 스케줄링한다.
    internal enum GtkMainQueue {
        /// `block`을 GTK 메인 스레드에 스케줄링한다. 또 어떤 스레드에서도 안전하게 호출할 수 있다.
        static func post(_ block: @escaping @MainActor () -> Void) {
            // 클로저를 힙 상의 박스에 담아 C 트램폴린에게 포인터를 넘긴다.
            // 이 박스는 트램폴린이 `block()` 실행을 끝낸 뒤 해제한다.
            let box = JobBox(block: block)
            let raw = Unmanaged.passRetained(box).toOpaque()
            ks_gtk_post_main_thread(gtkMainQueueTrampoline, raw)
        }
    }

    private final class JobBox: @unchecked Sendable {
        // @unchecked: GTK main loop dispatch \u2014 @MainActor closure captured for callback
        let block: @MainActor () -> Void
        init(block: @escaping @MainActor () -> Void) { self.block = block }
    }

    private let gtkMainQueueTrampoline:
        @convention(c) (
            UnsafeMutableRawPointer?
        ) -> Void = { raw in
            guard let raw else { return }
            let box = Unmanaged<JobBox>.fromOpaque(raw).takeRetainedValue()
            MainActor.assumeIsolated { box.block() }
        }

    extension GtkWebViewHost {
        /// GTK 메인 스레드로 클로저를 전달한다. 또 어떤 스레드에서도 안전하게
        /// 호출할 수 있다 (`g_idle_add` 래퍼).
        nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
            GtkMainQueue.post(block)
        }
    }
#endif
