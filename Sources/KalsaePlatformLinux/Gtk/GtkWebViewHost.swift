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

                          // 플랫폼 측에서 `invoke`가 reject하는 오류 객체는
                          // 항상 이 클래스의 인스턴스여서 `instanceof KalsaeError`로
                          // `.code`를 안전하게 읽을 수 있다.
                          class KalsaeError extends Error {
                            constructor(payload) {
                              const p = (payload && typeof payload === 'object') ? payload : {};
                              super(p.message || String(payload || 'Kalsae error'));
                              this.name = 'KalsaeError';
                              this.code = p.code || 'internal';
                              this.data = (p.data === undefined) ? null : p.data;
                            }
                          }
                          window.KalsaeError = KalsaeError;

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
                                if (msg.isError) p.reject(new KalsaeError(msg.payload));
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
                                // 30초 판 타임아웃 (RFC-005 §4.5)
                                const timer = setTimeout(() => {
                                  if (pending.has(id)) {
                                    pending.delete(id);
                                    reject(new KalsaeError({
                                      code: 'timeout',
                                      message: "invoke('" + cmd + "') timed out after 30000ms"
                                    }));
                                  }
                                }, 30000);
                                pending.set(id, {
                                  resolve(v) { clearTimeout(timer); resolve(v); },
                                  reject(e) { clearTimeout(timer); reject(e); },
                                });
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

                          // 편의를 위한 단축 함수. `KB` 객체에 위임한다.
                          function call(name, args) { return KB.invoke(name, args); }

                          // ---- 윈도우 ----
                          const Win = Object.freeze({
                            minimize:         () => call('__ks.window.minimize'),
                            maximize:         () => call('__ks.window.maximize'),
                            restore:          () => call('__ks.window.restore'),
                            toggleMaximize:   () => call('__ks.window.toggleMaximize'),
                            isMinimized:      () => call('__ks.window.isMinimized'),
                            isMaximized:      () => call('__ks.window.isMaximized'),
                            isFullscreen:     () => call('__ks.window.isFullscreen'),
                            isNormal:         () => call('__ks.window.isNormal'),
                            setFullscreen:    (enabled, window) => call('__ks.window.setFullscreen', { enabled: !!enabled, window: window || null }),
                            setAlwaysOnTop:   (enabled, window) => call('__ks.window.setAlwaysOnTop', { enabled: !!enabled, window: window || null }),
                            center:           () => call('__ks.window.center'),
                            setPosition:      (x, y, window) => call('__ks.window.setPosition', { x: x|0, y: y|0, window: window || null }),
                            getPosition:      () => call('__ks.window.getPosition'),
                            getSize:          () => call('__ks.window.getSize'),
                            setSize:          (width, height, window) => call('__ks.window.setSize', { width: width|0, height: height|0, window: window || null }),
                            setMinSize:       (width, height, window) => call('__ks.window.setMinSize', { width: width|0, height: height|0, window: window || null }),
                            setMaxSize:       (width, height, window) => call('__ks.window.setMaxSize', { width: width|0, height: height|0, window: window || null }),
                            setTitle:         (title, window) => call('__ks.window.setTitle', { title: String(title), window: window || null }),
                            show:             () => call('__ks.window.show'),
                            hide:             () => call('__ks.window.hide'),
                            focus:            () => call('__ks.window.focus'),
                            close:            () => call('__ks.window.close'),
                            reload:           () => call('__ks.window.reload'),
                            setTheme:         (theme, window) => call('__ks.window.setTheme', { theme: String(theme || 'system'), window: window || null }),
                            setBackgroundColor: (r, g, b, a, window) => call('__ks.window.setBackgroundColor', { r: (r|0)&0xFF, g: (g|0)&0xFF, b: (b|0)&0xFF, a: a === undefined ? 255 : (a|0)&0xFF, window: window || null }),
                            setCloseInterceptor: (enabled, window) => call('__ks.window.setCloseInterceptor', { enabled: !!enabled, window: window || null }),
                            setZoom:          (factor, window) => call('__ks.window.setZoom', { factor: Number(factor) || 1.0, window: window || null }),
                            getZoom:          () => call('__ks.window.getZoom'),
                            print:            (opts) => call('__ks.window.print', { systemDialog: !!(opts && opts.systemDialog), window: (opts && opts.window) || null }),
                            capturePreview:   (opts) => call('__ks.window.capturePreview', { format: (opts && opts.format) || 'png', window: (opts && opts.window) || null }),
                            displays:         () => call('__ks.window.displays'),
                            currentDisplay:   (window) => call('__ks.window.currentDisplay', window ? { window } : {}),
                            setTaskbarProgress: (type, value, window) => call('__ks.window.setTaskbarProgress', { progress: { type: String(type || 'none'), value: value !== undefined ? Number(value) : undefined }, window: window || null }),
                            setOverlayIcon:   (iconPath, description, window) => call('__ks.window.setOverlayIcon', { iconPath: iconPath || null, description: description || null, window: window || null }),
                            startDrag:        () => call('__ks.window.startDrag'),
                          });

                          // ---- 셸 ----
                          const Shell = Object.freeze({
                            openExternal:     (url) => call('__ks.shell.openExternal', { url: String(url) }),
                            showItemInFolder: (path) => call('__ks.shell.showItemInFolder', { url: String(path) }),
                            moveToTrash:      (path) => call('__ks.shell.moveToTrash', { url: String(path) }),
                          });

                          // ---- 다이얼로그 ----
                          const Dialog = Object.freeze({
                            openFile:     (opts) => call('__ks.dialog.openFile', opts || {}),
                            saveFile:     (opts) => call('__ks.dialog.saveFile', opts || {}),
                            selectFolder: (opts) => call('__ks.dialog.selectFolder', opts || {}),
                            message:      (opts) => call('__ks.dialog.message', opts || {}),
                          });

                          // ---- 클립보드 ----
                          const Clipboard = Object.freeze({
                            readText:  () => call('__ks.clipboard.readText'),
                            writeText: (text) => call('__ks.clipboard.writeText', { text: String(text) }),
                            clear:     () => call('__ks.clipboard.clear'),
                            hasFormat: (format) => call('__ks.clipboard.hasFormat', { format: String(format) }),
                          });

                          // ---- 앱 ----
                          const App = Object.freeze({
                            quit:        () => call('__ks.app.quit'),
                            environment: () => call('__ks.environment'),
                            hide:        () => call('__ks.window.hide'),
                            show:        () => call('__ks.window.show'),
                          });

                          // ---- 이벤트 ----
                          const Events = Object.freeze({
                            on(event, cb)   { return KB.listen(event, cb); },
                            off(event, cb)  {
                              const set = listeners.get(event);
                              if (set) set.delete(cb);
                            },
                            once(event, cb) {
                              const off = KB.listen(event, (payload) => {
                                try { off(); } finally { cb(payload); }
                              });
                              return off;
                            },
                            offAll(event)   {
                              if (event === undefined) listeners.clear();
                              else listeners.delete(event);
                            },
                            emit: KB.emit,
                          });

                          // ---- 로그 ----
                          function logAt(level) {
                            return function (...args) {
                              const text = args.map(a =>
                                (typeof a === 'string') ? a
                                  : (a instanceof Error) ? (a.stack || a.message)
                                  : (() => { try { return JSON.stringify(a); } catch (_) { return String(a); } })()
                              ).join(' ');
                              try { call('__ks.log', { level, message: text }).catch(() => {}); }
                              catch (_) { /* registry may not be wired yet */ }
                              const fn = console[level === 'trace' ? 'debug' : (level === 'warn' ? 'warn' : (level === 'error' ? 'error' : 'log'))];
                              try { fn.apply(console, args); } catch (_) {}
                            };
                          }
                          const Log = Object.freeze({
                            trace: logAt('trace'),
                            debug: logAt('debug'),
                            info:  logAt('info'),
                            warn:  logAt('warn'),
                            error: logAt('error'),
                          });

                          const Root = Object.freeze({
                            invoke: KB.invoke,
                            listen: KB.listen,
                            emit:   KB.emit,
                            window: Win,
                            shell:  Shell,
                            dialog: Dialog,
                            clipboard: Clipboard,
                            app:    App,
                            events: Events,
                            log:    Log,
                          });

                          window.__KS_ = Root;
                          if (!window.Kalsae) window.Kalsae = Root;

                          // ---- 드래그 영역 지원 (데스크톱 전용) ----
                          function isInteractive(el) {
                            if (!el || el.nodeType !== 1) return false;
                            const tag = el.tagName;
                            if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT'
                                || tag === 'BUTTON' || tag === 'A' || tag === 'OPTION'
                                || tag === 'VIDEO' || tag === 'AUDIO') return true;
                            if (el.isContentEditable) return true;
                            return false;
                          }
                          function regionOf(el) {
                            const cs = window.getComputedStyle(el);
                            const v = (cs.getPropertyValue('app-region')
                                    || cs.getPropertyValue('-webkit-app-region')
                                    || cs.getPropertyValue('--ks-app-region') || '').trim();
                            return v;
                          }
                          document.addEventListener('mousedown', function (ev) {
                            if (ev.button !== 0) return;
                            if (ev.ctrlKey || ev.shiftKey || ev.altKey || ev.metaKey) return;
                            let el = ev.target;
                            while (el && el.nodeType === 1) {
                              if (isInteractive(el)) return;
                              const r = regionOf(el);
                              if (r === 'no-drag') return;
                              if (r === 'drag') {
                                ev.preventDefault();
                                try { call('__ks.window.startDrag').catch(() => {}); } catch (_) {}
                                return;
                              }
                              el = el.parentNode;
                            }
                          }, true);
                          document.addEventListener('dblclick', function (ev) {
                            if (ev.button !== 0) return;
                            let el = ev.target;
                            while (el && el.nodeType === 1) {
                              if (isInteractive(el)) return;
                              const r = regionOf(el);
                              if (r === 'no-drag') return;
                              if (r === 'drag') {
                                ev.preventDefault();
                                try { call('__ks.window.toggleMaximize').catch(() => {}); } catch (_) {}
                                return;
                              }
                              el = el.parentNode;
                            }
                          }, true);

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

        /// 가장 최근 `navigate(url:)` 호출의 URL. IPC origin 평가용으로 사용된다.
        /// WebKitGTK 의 `webkit_web_view_get_uri` 바인딩이 추가되면 정확도가 향상된다.
        public private(set) var lastNavigatedURL: String?

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
            self.lastNavigatedURL = url
        }

        public func postJSON(_ json: String) throws(KSError) {
            // RFC-005 §4.8: U+2028/U+2029 이스케이프
            let safe =
                json
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            let script = "window.__KS_receive(\(safe));"
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

        public func startDrag() {
            _ = ks_gtk_host_start_drag(hostPtr)
        }

        public func displayCount() -> Int {
            Int(ks_gtk_host_get_display_count(hostPtr))
        }

        public func currentDisplayIndex() -> Int {
            Int(ks_gtk_host_get_current_display_index(hostPtr))
        }

        public func displayInfo(at index: Int) -> KSDisplayInfo? {
            var idBuf = [CChar](repeating: 0, count: 128)
            var nameBuf = [CChar](repeating: 0, count: 256)

            var x: Int32 = 0
            var y: Int32 = 0
            var width: Int32 = 0
            var height: Int32 = 0
            var workX: Int32 = 0
            var workY: Int32 = 0
            var workWidth: Int32 = 0
            var workHeight: Int32 = 0
            var scale: Double = 1.0
            var refreshRate: Int32 = 0
            var isPrimary: Int32 = 0

            let ok = idBuf.withUnsafeMutableBufferPointer { idPtr in
                nameBuf.withUnsafeMutableBufferPointer { namePtr in
                    ks_gtk_host_get_display_info(
                        hostPtr,
                        Int32(index),
                        idPtr.baseAddress,
                        idBuf.count,
                        namePtr.baseAddress,
                        nameBuf.count,
                        &x,
                        &y,
                        &width,
                        &height,
                        &workX,
                        &workY,
                        &workWidth,
                        &workHeight,
                        &scale,
                        &refreshRate,
                        &isPrimary)
                }
            }

            guard ok != 0 else { return nil }

            let id = String(cString: idBuf)
            let name = String(cString: nameBuf)
            return KSDisplayInfo(
                id: id,
                name: name,
                bounds: KSRect(
                    x: Int(x),
                    y: Int(y),
                    width: Int(width),
                    height: Int(height)),
                workArea: KSRect(
                    x: Int(workX),
                    y: Int(workY),
                    width: Int(workWidth),
                    height: Int(workHeight)),
                scaleFactor: scale,
                refreshRate: refreshRate > 0 ? Int(refreshRate) : nil,
                isPrimary: isPrimary != 0)
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

        // MARK: - RFC-008 §2.4 보안 핸들러

        /// 외부 URL 라우팅 콜백 박스. C 트램폴린의 ctx로 전달.
        private static var externalURLBox: Unmanaged<ExternalURLBox>?

        /// 우클릭 컨텍스트 메뉴 활성화 토글.
        public func setDefaultContextMenusEnabled(_ enabled: Bool) {
            ks_gtk_host_set_context_menu_enabled(hostPtr, enabled ? 1 : 0)
            if !enabled {
                // JS 레벨 보강: WebKitGTK 없는 디스트로(헤드리스 등)에서도
                // 동작하도록 user script도 함께 주입한다.
                _ = try? addDocumentCreatedScript(KSLinuxSecurityScripts.disableContextMenu)
            }
        }

        /// 외부 파일 드롭 허용 토글.
        public func setAllowExternalDrop(_ allow: Bool) {
            ks_gtk_host_set_allow_external_drop(hostPtr, allow ? 1 : 0)
            if !allow {
                _ = try? addDocumentCreatedScript(KSLinuxSecurityScripts.disableExternalDrop)
            }
        }

        /// 팝업 차단 + 외부 URL 라우팅 + 권한 거부 핸들러.
        /// Windows/macOS의 `installSecurityHandlers(allowPopups:openExternal:)`와 동등.
        public func installSecurityHandlers(
            allowPopups: Bool,
            openExternal: (@MainActor (String) -> Void)?
        ) throws(KSError) {
            // 이전 박스가 있으면 해제.
            Self.externalURLBox?.release()
            Self.externalURLBox = nil
            if !allowPopups {
                let box = ExternalURLBox(handler: openExternal)
                let um = Unmanaged.passRetained(box)
                Self.externalURLBox = um
                ks_gtk_host_set_popup_blocking(
                    hostPtr, 1, linuxExternalURLTrampoline, um.toOpaque())
            } else {
                ks_gtk_host_set_popup_blocking(hostPtr, 0, nil, nil)
            }
        }

        /// 파일 드롭 emitter — Linux에서는 WebKitGTK가 외부 GtkDropTarget 가로채기를
        /// 지원하지 않아 best-effort 경고로 등록만 한다.
        public func installFileDropEmitter() throws(KSError) {
            log.warning(
                "Linux installFileDropEmitter() is a stub — WebKitGTK does not expose "
                    + "an external drop interception API; tracked as Phase 4 follow-up.")
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

    // MARK: - RFC-008 §2.4 보안 트램폴린/박스

    // @unchecked: GTK callback box (read-only post-init) — handler invoked on main thread
    private final class ExternalURLBox: @unchecked Sendable {
        let handler: (@MainActor (String) -> Void)?
        init(handler: (@MainActor (String) -> Void)?) { self.handler = handler }
    }

    /// 외부 URL 핸들러 트램폴린 — GTK 메인 스레드에서 호출됨.
    private let linuxExternalURLTrampoline:
        @convention(c) (
            UnsafePointer<CChar>?, UnsafeMutableRawPointer?
        ) -> Void = { urlPtr, ctxPtr in
            guard let urlPtr, let ctxPtr else { return }
            let url = String(cString: urlPtr)
            let box = Unmanaged<ExternalURLBox>.fromOpaque(ctxPtr).takeUnretainedValue()
            MainActor.assumeIsolated {
                box.handler?(url)
            }
        }

    /// JS 사용자 스크립 — WebKit signal과 함께 이중방어 역할.
    internal enum KSLinuxSecurityScripts {
        internal static let disableContextMenu: String = """
            (function(){
              const block = (e) => { e.preventDefault(); return false; };
              if (document.body) {
                document.addEventListener('contextmenu', block, { capture: true });
              } else {
                document.addEventListener('DOMContentLoaded', () => {
                  document.addEventListener('contextmenu', block, { capture: true });
                });
              }
            })();
            """
        internal static let disableExternalDrop: String = """
            (function(){
              const isExternal = (e) => {
                if (!e.dataTransfer) return false;
                for (const t of e.dataTransfer.types) {
                  if (t === 'Files') return true;
                }
                return false;
              };
              const block = (e) => { if (isExternal(e)) e.preventDefault(); };
              const install = () => {
                document.addEventListener('dragover', block, { capture: true });
                document.addEventListener('drop', block, { capture: true });
              };
              if (document.body) install();
              else document.addEventListener('DOMContentLoaded', install);
            })();
            """
    }
#endif
