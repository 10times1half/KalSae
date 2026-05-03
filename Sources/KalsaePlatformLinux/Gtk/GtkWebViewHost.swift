#if os(Linux)
    internal import CKalsaeGtk
    internal import Logging
    public import KalsaeCore
    public import Foundation

    /// Linux WebView에 주입되는 브리지 JavaScript. Windows/macOS와 동일한
    /// 역할을 하지만 `window.__KS_.invoke/listen/emit`을 노출한다.
    /// 통신: JS→Swift는 `window.webkit.messageHandlers.ks.postMessage(obj)`;
    /// Swift→JS는 `window.__KS_receive(obj)` (evaluate_javascript로 전달).
    internal enum KSRuntimeJS {
        static let source: String = #"""
                                    (function () {
                          if (window.__KS_) return;
                          const pending = new Map();
                          const listeners = new Map();
                          let nextId = 1;

                          function nativePost(obj) {
                            try {
                              window.webkit.messageHandlers.ks.postMessage(obj);
                            } catch (e) {
                              console.error('[KB] postMessage failed', e);
                            }
                          }

                          function handleInbound(msg) {
                            if (!msg || typeof msg !== 'object') return;
                            switch (msg.kind) {
                              case 'response': {
                                const p = pending.get(msg.id);
                                if (!p) return;
                                pending.delete(msg.id);
                                if (msg.isError) p.reject(msg.payload);
                                else p.resolve(msg.payload);
                                break;
                              }
                              case 'event': {
                                const set = listeners.get(msg.name);
                                if (!set) return;
                                for (const fn of set) {
                                  try { fn(msg.payload); } catch (e) { console.error(e); }
                                }
                                break;
                              }
                            }
                          }

                          const KB = Object.freeze({
                            invoke(cmd, args) {
                              return new Promise((resolve, reject) => {
                                const id = String(nextId++);
                                pending.set(id, { resolve, reject });
                                nativePost({
                                  kind: 'invoke',
                                  id,
                                  name: cmd,
                                  payload: args === undefined ? null : args,
                                });
                              });
                            },
                            listen(event, cb) {
                              if (typeof cb !== 'function') throw new TypeError('callback required');
                              let set = listeners.get(event);
                              if (!set) { set = new Set(); listeners.set(event, set); }
                              set.add(cb);
                              return () => set.delete(cb);
                            },
                            emit(event, payload) {
                              nativePost({
                                kind: 'event',
                                name: event,
                                payload: payload === undefined ? null : payload,
                              });
                            },
                          });

                          window.__KS_ = KB;
                          if (!window.Kalsae) window.Kalsae = KB;
                          window.__KS_receive = handleInbound;
                        })();
            """#
    }

    /// `CKalsaeGtk`를 감싸는 Swift 래퍼. `KSGtkHost*`를 소유하며
    /// `GtkBridge`를 통해 IPC 코어와 연결된다. `WebView2Host` /
    /// `WKWebViewHost`와 동일한 역할을 한다.
    @MainActor
    public final class GtkWebViewHost {
        /// C 함수가 소유한 C opaque 포인터. hostPtr은 nonisolated 컨텍스트
        /// (e.g. `postJob`)에서도 읽을 수 있어야 한다.
        nonisolated(unsafe) internal var hostPtr: OpaquePointer?

        private let log: Logger = KSLog.logger("platform.linux.webview")
        private var inbound: ((String) -> Void)?

        /// C 콜백 트램폴린에 self를 전달하기 위한 힙 할당 홀더.
        /// Swift의 약한 참조를 통해 retain cycle을 방지한다.
        private var selfBox: SelfBox?

        public init(appId: String, title: String, width: Int, height: Int) {
            self.hostPtr = ks_gtk_host_new(
                appId, title,
                Int32(width), Int32(height))

            ks_gtk_host_add_user_script(hostPtr, KSRuntimeJS.source)

            let box = SelfBox(owner: self)
            self.selfBox = box
            let ctx = Unmanaged.passUnretained(box).toOpaque()
            ks_gtk_host_set_message_handler(
                hostPtr,
                gtkBridgeMessageTrampoline,
                ctx)
            log.info("GtkWebViewHost initialized (\(title))")
        }

        deinit {
            if let p = hostPtr {
                ks_gtk_host_free(p)
            }
        }

        public func onMessage(_ handler: @escaping @MainActor (String) -> Void) throws(KSError) {
            self.inbound = handler
        }

        fileprivate func deliverInbound(_ text: String) {
            inbound?(text)
        }

        public func navigate(url: String) throws(KSError) {
            ks_gtk_host_load_uri(hostPtr, url)
        }

        public func postJSON(_ json: String) throws(KSError) {
            let script = "window.__KS_receive(\(json));"
            ks_gtk_host_eval_js(hostPtr, script)
        }

        public func openDevToolsNow() throws(KSError) {
            ks_gtk_host_open_devtools(hostPtr)
        }

        public func setTitle(_ title: String) {
            ks_gtk_host_set_title(hostPtr, title)
        }

        public func setSize(width: Int, height: Int) {
            ks_gtk_host_set_size(hostPtr, Int32(width), Int32(height))
        }

        public func show() {
            ks_gtk_host_show(hostPtr)
        }

        public func hide() {
            ks_gtk_host_hide(hostPtr)
        }

        public func focus() {
            ks_gtk_host_focus(hostPtr)
        }

        public func reload() {
            ks_gtk_host_reload(hostPtr)
        }

        public func minimize() {
            ks_gtk_host_minimize(hostPtr)
        }

        public func maximize() {
            ks_gtk_host_maximize(hostPtr)
        }

        public func unmaximize() {
            ks_gtk_host_unmaximize(hostPtr)
        }

        public func isMaximized() -> Bool {
            ks_gtk_host_is_maximized(hostPtr) != 0
        }

        public func isMinimized() -> Bool {
            ks_gtk_host_is_minimized(hostPtr) != 0
        }

        public func setFullscreen(_ enabled: Bool) {
            if enabled {
                ks_gtk_host_fullscreen(hostPtr)
            } else {
                ks_gtk_host_unfullscreen(hostPtr)
            }
        }

        public func isFullscreen() -> Bool {
            ks_gtk_host_is_fullscreen(hostPtr) != 0
        }

        public func getSize() -> KSSize? {
            var w: Int32 = 0
            var h: Int32 = 0
            let ok = ks_gtk_host_get_size(hostPtr, &w, &h)
            guard ok != 0 else { return nil }
            return KSSize(width: Int(w), height: Int(h))
        }

        public func setZoomLevel(_ level: Double) {
            ks_gtk_host_set_zoom_level(hostPtr, level)
        }

        public func getZoomLevel() -> Double {
            ks_gtk_host_get_zoom_level(hostPtr)
        }

        public func setBackgroundColor(r: Float, g: Float, b: Float, a: Float) {
            ks_gtk_host_set_background_color(hostPtr, r, g, b, a)
        }

        public func setTheme(_ theme: KSWindowTheme) {
            let code: Int32
            switch theme {
            case .dark: code = 2
            case .light: code = 1
            case .system: code = 0
            }
            ks_gtk_host_set_theme(hostPtr, code)
        }

        public func setMinSize(width: Int, height: Int) {
            ks_gtk_host_set_min_size(hostPtr, Int32(width), Int32(height))
        }

        public func setMaxSize(width: Int, height: Int) {
            ks_gtk_host_set_max_size(hostPtr, Int32(width), Int32(height))
        }

        public func setPosition(x: Int, y: Int) {
            ks_gtk_host_set_position(hostPtr, Int32(x), Int32(y))
        }

        public func getPosition() -> KSPoint? {
            var x: Int32 = 0
            var y: Int32 = 0
            guard ks_gtk_host_get_position(hostPtr, &x, &y) != 0 else { return nil }
            return KSPoint(x: Double(x), y: Double(y))
        }

        public func centerOnScreen() {
            ks_gtk_host_center(hostPtr)
        }

        public func setCloseInterceptor(_ enabled: Bool) {
            ks_gtk_host_set_close_interceptor(hostPtr, enabled ? 1 : 0)
        }

        public func setKeepAbove(_ enabled: Bool) {
            ks_gtk_host_set_keep_above(hostPtr, enabled ? 1 : 0)
        }

        public func showPrintUI(systemDialog: Bool) {
            ks_gtk_host_show_print_ui(hostPtr, systemDialog ? 1 : 0)
        }

        public func capturePreview(format: Int32) async throws(KSError) -> Data {
            // @unchecked: GTK callback box (read-only post-init) — passed as opaque context to C
            final class SnapshotBox: @unchecked Sendable {
                var cont: CheckedContinuation<Data, any Error>?
            }
            let box = SnapshotBox()
            do {
                let data: Data = try await withCheckedThrowingContinuation {
                    (cont: CheckedContinuation<Data, any Error>) in
                    box.cont = cont
                    let um = Unmanaged.passRetained(box)
                    ks_gtk_host_capture_preview(
                        hostPtr,
                        format,
                        { bytes, len, ctx in
                            let b = Unmanaged<SnapshotBox>.fromOpaque(ctx!).takeRetainedValue()
                            if let bytes, len > 0 {
                                b.cont?.resume(returning: Data(bytes: bytes, count: len))
                            } else {
                                b.cont?.resume(
                                    throwing: KSError(
                                        code: .webviewInitFailed,
                                        message: "capturePreview: snapshot failed"))
                            }
                        },
                        um.toOpaque())
                }
                return data
            } catch {
                throw error as? KSError
                    ?? KSError(code: .internal, message: "\(error)")
            }
        }

        /// `root`에서 에셋을 제공하도록 `ks://` 스킴 핸들러를 바인딩한다.
        /// `run()` 이전에 호출해야 한다. WebKit의 스킴 핸들러는
        /// 한 번 설정되면 교체할 수 없으므로 최초 한 번만 호출한다.
        public func setAssetRoot(_ root: URL) throws(KSError) {
            let resolver = KSAssetResolver(root: root)
            let box = ResolverBox(resolver: resolver)
            // 이전 박스를 해제한다. C 트램폴린이 더 이상 참조하지 않음을 보장한다.
            self.resolverBox?.release()
            let um = Unmanaged.passRetained(box)
            self.resolverBox = um
            ks_gtk_host_set_scheme_resolver(
                hostPtr, linuxSchemeResolverTrampoline, um.toOpaque())
        }

        /// 모든 문서 시작 시 실행될 JS 스니펫을 대기열에 추가한다.
        public func addDocumentCreatedScript(_ script: String) throws(KSError) {
            ks_gtk_host_add_user_script(hostPtr, script)
        }

        /// `ks://` 응답에 적용할 Content-Security-Policy 헤더를 설정한다.
        /// `setAssetRoot`보다 먼저 호출해야 스킴 핸들러가 생성될 때 적용된다.
        public func setResponseCSP(_ csp: String) throws(KSError) {
            ks_gtk_host_set_response_csp(hostPtr, csp)
        }

        /// 자산 응답에 Cross-Origin Isolation 헤더(COOP/COEP/CORP) 자동 추가 여부를
        /// 토글한다. `KSSecurityConfig.crossOriginIsolation`에 대응한다.
        public func setCrossOriginIsolation(_ enabled: Bool) {
            ks_gtk_host_set_cross_origin_isolation(hostPtr, enabled ? 1 : 0)
        }

        private var resolverBox: Unmanaged<ResolverBox>?

        // MARK: - Window state persistence

        /// 복원할 윈도우 상태를 등록한다. `run()` 호출(=activate) 이전에
        /// 호출되어야 한다. Wayland에서는 위치 정보가 무시되고
        /// X11에서만 위치가 복원된다.
        /// 최대화/전체화면 상태는 모든 환경에서 복원된다.
        public func applyRestoredState(_ state: KSPersistedWindowState) {
            // 참고: Wayland에서는 위치가 무시되고 X11에서만 위치가 복원된다.
            // C 트램폴린이 X11 surface 유무를 감지해 has_position=1로 설정한다.
            ks_gtk_host_set_pending_restore_state(
                hostPtr,
                Int32(state.x), Int32(state.y),
                Int32(state.width), Int32(state.height),
                1,  // has_position
                state.maximized ? 1 : 0,
                state.fullscreen ? 1 : 0)
        }

        /// 윈도우 상태 저장 sink를 등록한다. close-request 시점에
        /// 메인 스레드에서 동기적으로 호출된다. `nil`을 전달하면 제거된다.
        public func setWindowStateSaveSink(
            _ sink: (@MainActor (KSPersistedWindowState) -> Void)?
        ) {
            // 이전 박스를 해제한다.
            stateSaveBox?.release()
            stateSaveBox = nil

            guard let sink else {
                ks_gtk_host_set_state_save_handler(hostPtr, nil, nil)
                return
            }
            let box = StateSaveBox(sink: sink)
            let um = Unmanaged.passRetained(box)
            stateSaveBox = um
            ks_gtk_host_set_state_save_handler(
                hostPtr,
                linuxStateSaveTrampoline,
                um.toOpaque())
        }

        private var stateSaveBox: Unmanaged<StateSaveBox>?

        /// 현재 윈도우 상태를 조회한다. C 트램폴린이 윈도우 상태를
        /// 읽어 반환한다. 실패 시 `nil`을 반환한다.
        public func currentWindowState() -> KSPersistedWindowState? {
            var x: Int32 = 0
            var y: Int32 = 0
            var w: Int32 = 0
            var h: Int32 = 0
            var hasPos: Int32 = 0
            var maximized: Int32 = 0
            var fullscreen: Int32 = 0
            let ok = ks_gtk_host_get_window_state(
                hostPtr, &x, &y, &w, &h,
                &hasPos, &maximized, &fullscreen)
            guard ok != 0 else { return nil }
            return KSPersistedWindowState(
                x: hasPos != 0 ? Int(x) : 0,
                y: hasPos != 0 ? Int(y) : 0,
                width: Int(w),
                height: Int(h),
                maximized: maximized != 0,
                fullscreen: fullscreen != 0)
        }

        /// Runs the GtkApplication's main loop until quit. Blocks.
        internal func run() -> Int32 {
            ks_gtk_host_run(hostPtr, 0, nil)
        }

        /// Requests an orderly shutdown of the Gtk application.
        internal func quit() {
            ks_gtk_host_quit(hostPtr)
        }
    }

    /// Owns a `KSAssetResolver` for the duration of the scheme handler's
    /// lifetime. Read-only from C side.
    // @unchecked: GTK callback box (read-only post-init) — passed as opaque context to C
    private final class ResolverBox: @unchecked Sendable {
        let resolver: KSAssetResolver
        init(resolver: KSAssetResolver) { self.resolver = resolver }
    }

    /// Holder for the window-state-save sink. Read-only from C side.
    // @unchecked: GTK callback box (read-only post-init) — passed as opaque context to C
    private final class StateSaveBox: @unchecked Sendable {
        let sink: @MainActor (KSPersistedWindowState) -> Void
        init(sink: @escaping @MainActor (KSPersistedWindowState) -> Void) {
            self.sink = sink
        }
    }

    /// C-side state-save trampoline. Runs on the GTK main thread.
    private let linuxStateSaveTrampoline:
        @convention(c) (
            Int32, Int32, Int32, Int32,
            Int32, Int32, Int32,
            UnsafeMutableRawPointer?
        ) -> Void = { x, y, w, h, hasPos, maximized, fullscreen, ctx in
            guard let ctx else { return }
            let box = Unmanaged<StateSaveBox>.fromOpaque(ctx).takeUnretainedValue()
            let state = KSPersistedWindowState(
                x: hasPos != 0 ? Int(x) : 0,
                y: hasPos != 0 ? Int(y) : 0,
                width: Int(w),
                height: Int(h),
                maximized: maximized != 0,
                fullscreen: fullscreen != 0)
            MainActor.assumeIsolated {
                box.sink(state)
            }
        }

    /// C-side scheme trampoline. Runs on the GTK main thread. Reads the
    /// asset via `KSAssetResolver` and returns bytes via `g_malloc`'d
    /// buffers the C shim hands to `g_memory_input_stream_new_from_data`.
    private let linuxSchemeResolverTrampoline:
        @convention(c) (
            UnsafePointer<CChar>?,
            UnsafeMutableRawPointer?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
            UnsafeMutablePointer<Int>?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> Int32 = { pathPtr, ctxPtr, outData, outLen, outMime in
            guard let pathPtr, let ctxPtr,
                let outData, let outLen
            else { return -1 }
            let path = String(cString: pathPtr)
            let box = Unmanaged<ResolverBox>.fromOpaque(ctxPtr).takeUnretainedValue()
            do {
                let asset = try box.resolver.resolve(path: path)
                // C 트램폴린이 g_free로 해제할 수 있도록 malloc으로 할당한다(glib malloc과
                // 동일한 힙을 사용한다고 가정). Swift의 libc malloc과 동일한 힙이므로
                // 안전하다.
                let size = asset.data.count
                let buf = UnsafeMutableRawPointer.allocate(
                    byteCount: size, alignment: 1)
                asset.data.withUnsafeBytes { src in
                    if let base = src.baseAddress {
                        buf.copyMemory(from: base, byteCount: size)
                    }
                }
                outData.pointee = buf.assumingMemoryBound(to: CChar.self)
                outLen.pointee = size

                if let outMime {
                    let mime = asset.mimeType
                    let mimeBytes = Array(mime.utf8) + [0]
                    let mimeBuf = UnsafeMutablePointer<CChar>.allocate(
                        capacity: mimeBytes.count)
                    mimeBytes.withUnsafeBufferPointer { src in
                        if let base = src.baseAddress {
                            for i in 0..<mimeBytes.count {
                                mimeBuf[i] = CChar(bitPattern: base[i])
                            }
                        }
                    }
                    outMime.pointee = mimeBuf
                }
                return 0
            } catch {
                return -1
            }
        }

    /// Holder used to pass `self` through a C callback as opaque context.
    /// `@unchecked Sendable` because it's only ever read from the GTK main
    /// thread.
    // @unchecked: GTK callback box (read-only post-init) — weak ref captured in C callback
    private final class SelfBox: @unchecked Sendable {
        weak var owner: GtkWebViewHost?
        init(owner: GtkWebViewHost) { self.owner = owner }
    }

    /// C-side trampoline. Bridges NUL-terminated JSON from WebKitGTK into
    /// the Swift host's `inbound` handler on the main actor.
    private let gtkBridgeMessageTrampoline:
        @convention(c) (
            UnsafePointer<CChar>?, UnsafeMutableRawPointer?
        ) -> Void = { jsonPtr, ctxPtr in
            guard let jsonPtr, let ctxPtr else { return }
            let text = String(cString: jsonPtr)
            let box = Unmanaged<SelfBox>.fromOpaque(ctxPtr).takeUnretainedValue()
            MainActor.assumeIsolated {
                box.owner?.deliverInbound(text)
            }
        }

    nonisolated(unsafe) private let _gtkKSPostEncoder = JSONEncoder()
    @MainActor
    extension GtkWebViewHost: KSWebViewBackend {
        public func load(url: URL) async throws(KSError) {
            try navigate(url: url.absoluteString)
        }

        @discardableResult
        public func evaluateJavaScript(_ source: String) async throws(KSError) -> Data? {
            ks_gtk_host_eval_js(hostPtr, source)
            // CKalsaeGtk currently exposes fire-and-forget JS evaluation.
            return nil
        }

        public func postMessage(_ message: KSIPCMessage) async throws(KSError) {
            let data = try _gtkKSPostEncoder.encode(message)
            guard let json = String(data: data, encoding: .utf8) else {
                throw KSError(code: .internal, message: "postMessage: JSON encoding failed")
            }
            try postJSON(json)
        }

        public func setMessageHandler(
            _ handler: @Sendable @escaping (KSIPCMessage) async -> Void
        ) async {
            do {
                try onMessage { text in
                    guard let data = text.data(using: .utf8),
                        let msg = try? JSONDecoder().decode(KSIPCMessage.self, from: data)
                    else { return }
                    Task {
                        await handler(msg)
                    }
                }
            } catch {
                KSLog.logger("platform.linux.webview").warning(
                    "setMessageHandler install failed: \(error)")
            }
        }

        public func setContentSecurityPolicy(_ csp: String) async throws(KSError) {
            try setResponseCSP(csp)
        }

        public func openDevTools() async throws(KSError) {
            try openDevToolsNow()
        }
    }
#endif
