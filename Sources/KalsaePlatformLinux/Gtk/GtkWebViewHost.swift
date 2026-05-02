#if os(Linux)
    internal import CKalsaeGtk
    internal import Logging
    public import KalsaeCore
    public import Foundation

    /// ?怨쀫춦筌띾뜆???????뽰젫??JS ?怨??? Windows/macOS ?怨??袁㏓궢 ??덉뵬??    /// ?④쑴鍮? `window.__KS_.invoke/listen/emit`.
    /// ?袁⑸꽊: JS?萸냭ift??`window.webkit.messageHandlers.ks.postMessage(obj)`;
    /// Swift?臾쿞??`window.__KS_receive(obj)` (evaluate_javascript嚥??紐꾪뀱).
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

    /// `CKalsaeGtk`????????? Swift ??묐쓠. `KSGtkHost*`????????랁?    /// `GtkBridge`揶쎛 ?袁⑹뒄嚥???롫뮉 ?臾? ?紐낃숲??륁뵠??? ?紐꾪뀱??뺣뼄.
    /// `WebView2Host` / `WKWebViewHost`?? ???臾볥립??
    @MainActor
    public final class GtkWebViewHost {
        /// ?븍뜇?억쭗?C ?紐꾨뮞??????? C ??깆뵠?됰슢??뵳???筌롫뗄???룐뫂遊????살쟿???癒곕늄?紐꾩뵠筌왖筌?        /// nonisolated ??묐쓠(e.g. `postJob`)?癒?퐣 ??????怨? ??뚮선????
        nonisolated(unsafe) fileprivate var hostPtr: OpaquePointer?

        private let log: Logger = KSLog.logger("platform.linux.webview")
        private var inbound: ((String) -> Void)?

        /// C 筌롫뗄?놅쭪? ?紐껋삪??????븍뜇?억쭗??뚢뫂???쎈뱜 ????怨? ???퉸
        /// ??Swift 揶쏆빘猿쒏에????툡??????덈즲嚥??醫???롫뮉 ??疫?獄쏅벡??
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
            // @unchecked: GTK callback box (read-only post-init) ??passed as opaque context to C
            final class SnapshotBox: @unchecked Sendable {
                var cont: CheckedContinuation<Data, Error>?
            }
            let box = SnapshotBox()
            let data: Data = try await withCheckedThrowingContinuation { cont in
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
        }

        /// `root`?癒?퐣 ?癒?????볥궗??롫즲嚥?`ks://` ??쎄땀 ?紐껊굶??? 獄쏅뗄???븍립??
        /// `run()` ?袁⑸퓠 ?紐꾪뀱??곷튊 ??뺣뼄 ??WebKit?? ???뚢뫂???쎈뱜
        /// ??밴쉐 ??뽯퓠筌???쎄땀 ?紐껊굶??? ?源낆쨯??뺣뼄.
        public func setAssetRoot(_ root: URL) throws(KSError) {
            let resolver = KSAssetResolver(root: root)
            let box = ResolverBox(resolver: resolver)
            // ??곸읈 ?귐듽뚩린袁? ?대Ŋ猿??뺣뼄. C 筌잛럩肉????μ뵬 ???숋쭕?鈺곕똻??
            self.resolverBox?.release()
            let um = Unmanaged.passRetained(box)
            self.resolverBox = um
            ks_gtk_host_set_scheme_resolver(
                hostPtr, linuxSchemeResolverTrampoline, um.toOpaque())
        }

        /// 筌뤴뫀諭??얜챷苑???뽰삂 ????쎈뻬??JS ??삳빍??ъ뱽 ??疫꿸퀣肉???곕떽???뺣뼄.
        public func addDocumentCreatedScript(_ script: String) throws(KSError) {
            ks_gtk_host_add_user_script(hostPtr, script)
        }

        /// `ks://` ?臾먮뼗筌띾뜄??獄쏆뮉六??롫뮉 Content-Security-Policy ??삳쐭????쇱젟??뺣뼄.
        /// `setAssetRoot`?? ??끸뵲?怨몄뵠筌? ??쎄땀 ?紐껊굶??? ?癒?????볥궗?????춳???怨몄뒠??뺣뼄.
        public func setResponseCSP(_ csp: String) throws(KSError) {
            ks_gtk_host_set_response_csp(hostPtr, csp)
        }

        private var resolverBox: Unmanaged<ResolverBox>?

        // MARK: - Window state persistence

        /// ??뽮쉐???袁⑸퓠 ?怨몄뒠??癰귣벊???怨밴묶???紐꾨뮞?紐꾨퓠 癰귣떯???뺣뼄.
        /// `run()` ?紐꾪뀱 ??=activate 獄쏆뮇源????癒?춸 ???揶쎛 ??덈뼄.
        /// Wayland?癒?퐣 ?袁⑺뒄???뚮똾猷뤄쭪??怨? ???젫???嚥??얜똻???렽? ??由?筌ㅼ뮆???
        /// ?袁⑷퍥?遺얇늺?? 筌뤴뫀諭???띻펾?癒?퐣 ?怨몄뒠??뺣뼄.
        public func applyRestoredState(_ state: KSPersistedWindowState) {
            // ?類ㅼ퐠: ?袁⑺뒄??Wayland?癒?퐣 ?얜똻????筌? X11?癒?퐣???怨몄뒠??뺣뼄.
            // C 筌β돦肉??X11 surface ?????野꺜??釉?첋?嚥???湲?has_position=1嚥??袁⑤뼎.
            ks_gtk_host_set_pending_restore_state(
                hostPtr,
                Int32(state.x), Int32(state.y),
                Int32(state.width), Int32(state.height),
                1,  // has_position
                state.maximized ? 1 : 0,
                state.fullscreen ? 1 : 0)
        }

        /// ??덈즲???怨밴묶 ????sink???源낆쨯??뺣뼄. close-request ??뽰젎??        /// 筌롫뗄????살쟿??뽯퓠????녿┛?怨몄몵嚥??紐꾪뀱??뺣뼄. `nil` ?袁⑤뼎 ????곸젫.
        public func setWindowStateSaveSink(
            _ sink: (@MainActor (KSPersistedWindowState) -> Void)?
        ) {
            // ??곸읈 獄쏅벡????곸젫.
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

        /// ?袁⑹삺 ??덈즲???怨밴묶????녿┛ 鈺곌퀬?? C 筌β돦肉???덈즲?怨? ?袁⑹춦
        /// 筌띾슢諭???筌왖 ??? 野껋럩??`nil`??獄쏆꼹???뺣뼄.
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
    // @unchecked: GTK callback box (read-only post-init) ??passed as opaque context to C
    private final class ResolverBox: @unchecked Sendable {
        let resolver: KSAssetResolver
        init(resolver: KSAssetResolver) { self.resolver = resolver }
    }

    /// Holder for the window-state-save sink. Read-only from C side.
    // @unchecked: GTK callback box (read-only post-init) ??passed as opaque context to C
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
                // C 筌잛럩肉??g_free???紐꾪뀱??????덈즲嚥?malloc??곗쨮 ?醫딅뼣??뺣뼄(glib malloc??
                // 筌왖?癒?┷??筌뤴뫀諭????삸??깅퓠??libc malloc???怨뱀깈 ??곸뒠 揶쎛??.
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
    // @unchecked: GTK callback box (read-only post-init) ??weak ref captured in C callback
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
            let data = try JSONEncoder().encode(message)
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
