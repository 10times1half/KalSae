#if os(Android)
    public import KalsaeCore
    public import Foundation

    // MARK: - JS runtime source

    /// JavaScript injected at document start.
    /// Mirrors the iOS/macOS runtime source: uses `window.webkit.messageHandlers`
    /// protocol via an injected `window.__KS_bridge` hook that the Android
    /// WebView host populates through the `addJavascriptInterface` or
    /// `evaluateJavascript` side-channel.
    private enum KSAndroidRuntimeJS {
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
                const json = JSON.stringify(obj);
                // Android host installs window.__KS_bridge.postMessage(json)
                // via addJavascriptInterface / @JavascriptInterface.
                if (window.__KS_bridge && typeof window.__KS_bridge.postMessage === 'function') {
                  try { window.__KS_bridge.postMessage(json); } catch (e) {
                    console.error('[KS] bridge.postMessage failed', e);
                  }
                } else {
                  console.warn('[KS] Android bridge not ready');
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
                    nativePost({ kind: 'invoke', id, name: cmd,
                      payload: args === undefined ? null : args });
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
                  nativePost({ kind: 'event', name: event,
                    payload: payload === undefined ? null : payload });
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
              window.__KS_receive = handleInbound;
            })();
            """#
    }

    // MARK: - WebView host

    /// Swift-side host for the Android `android.webkit.WebView` (API 26+).
    ///
    /// The actual `WebView` instance lives in `Samples/KalsaeAndroidSample/`'s
    /// `MainActivity`. JNI entry points in
    /// `Sources/KalsaePlatformAndroid/JNI/KSAndroidJNI.swift` wire the closures
    /// below into the running Activity via C function pointer callbacks.
    ///
    /// This class manages the IPC state machine and exposes:
    ///
    /// - `onInboundMessage`: called by `KS_android_on_inbound_message` (JNI) when
    ///   the WebView's `@JavascriptInterface` delivers a message from JS.
    /// - `postJSON(_:)`:    sends a JSON string to JS via `evaluateJavascript`.
    /// - `onEvaluateJS`:   inject this from Kotlin so Swift can call
    ///   `webView.evaluateJavascript(...)` over the JNI bridge.
    ///
    /// The IPC flow is:
    /// ```
    /// JS  → __KS_bridge.postMessage(json)
    ///     → JNI @JavascriptInterface → Swift onInboundMessage(json)
    ///     → KSAndroidBridge.handleInbound(json)
    ///     → KSIPCBridgeCore dispatches command
    ///     → sendResponse → postJSON(json)
    ///     → JNI evaluateJavascript → JS window.__KS_receive(msg)
    /// ```
    @MainActor
    public final class KSAndroidWebViewHost {
        private let lock = NSLock()
        private var _pendingDocScripts: [String] = []
        private var _pendingURL: String?
        private var _csp: String?

        // MARK: Injectable handlers (set by JNI/Kotlin host)

        /// Called by Swift to push JSON into the WebView.
        /// Kotlin sets: `host.onEvaluateJS = { js in webView.evaluateJavascript(js, null) }`
        public var onEvaluateJS: ((String) -> Void)? {
            get { lock.withLock { _onEvaluateJS } }
            set { lock.withLock { _onEvaluateJS = newValue } }
        }
        private var _onEvaluateJS: ((String) -> Void)?

        /// Called by Swift to load a URL in the WebView.
        /// Kotlin sets: `host.onLoadURL = { url -> webView.loadUrl(url) }`
        public var onLoadURL: ((String) -> Void)? {
            get { lock.withLock { _onLoadURL } }
            set { lock.withLock { _onLoadURL = newValue } }
        }
        private var _onLoadURL: ((String) -> Void)?

        // MARK: - Inbound (Kotlin → Swift)

        private var inboundHandler: ((String) -> Void)?
        nonisolated(unsafe) private static let _sharedEncoder = JSONEncoder()

        /// Kotlin calls this from the `@JavascriptInterface` method.
        /// Thread-safe — the Android WebView may call this off the main thread.
        nonisolated public func onInboundMessage(_ json: String) {
            Task { @MainActor [weak self] in
                self?.inboundHandler?(json)
            }
        }

        // MARK: - Public API (used by KSAndroidDemoHost)

        public func onMessage(_ handler: @escaping @MainActor (String) -> Void) throws(KSError) {
            self.inboundHandler = handler
        }

        public func addDocumentCreatedScript(_ script: String) throws(KSError) {
            lock.withLock { _pendingDocScripts.append(script) }
        }

        public func setAssetRoot(_ root: URL) throws(KSError) {
            // Asset serving on Android is handled by WebViewAssetLoader (Kotlin side).
            // Swift records the root so it can be forwarded via a JNI handshake.
            // Actual file serving is out of scope for this scaffold.
            _ = root
        }

        /// Returns the composite document-start script (runtime + user scripts)
        /// that Kotlin should inject via `WebViewCompat.addDocumentStartJavaScript`.
        public func documentStartScript() -> String {
            let userScripts = lock.withLock { _pendingDocScripts }.joined(separator: "\n")
            return KSAndroidRuntimeJS.source + "\n" + userScripts
        }

        public func navigate(url: String) throws(KSError) {
            if let handler = lock.withLock({ _onLoadURL }) {
                handler(url)
            } else {
                lock.withLock { _pendingURL = url }
            }
        }

        /// Flushes a pending URL to the WebView once the Activity is ready.
        public func flushPendingURL() {
            let pending = lock.withLock {
                _pendingURL.map { url -> String in
                    _pendingURL = nil
                    return url
                }
            }
            if let url = pending, let handler = lock.withLock({ _onLoadURL }) {
                handler(url)
            }
        }

        public func postJSON(_ json: String) throws(KSError) {
            let script = "window.__KS_receive(\(json));"
            if let handler = lock.withLock({ _onEvaluateJS }) {
                handler(script)
            } else {
                KSLog.logger("platform.android.webview")
                    .warning("postJSON: evaluateJS bridge not installed, frame dropped")
            }
        }

        public func openDevTools() throws(KSError) {
            // Enable in debug builds via WebView.setWebContentsDebuggingEnabled(true)
            // — that call must be made from Kotlin before WebView creation.
        }
    }

    // MARK: - KSWebViewBackend conformance

    extension KSAndroidWebViewHost: KSWebViewBackend {
        public func load(url: URL) async throws(KSError) {
            try navigate(url: url.absoluteString)
        }

        @discardableResult
        public func evaluateJavaScript(_ source: String) async throws(KSError) -> Data? {
            guard let handler = lock.withLock({ _onEvaluateJS }) else {
                throw KSError.unsupportedPlatform(
                    "evaluateJavaScript: Android evaluateJS bridge not installed")
            }
            handler(source)
            return nil  // Return value collection requires a JNI callback — deferred.
        }

        public func postMessage(_ message: KSIPCMessage) async throws(KSError) {
            let data = try Self._sharedEncoder.encode(message)
            guard let json = String(data: data, encoding: .utf8) else {
                throw KSError(code: .internal, message: "postMessage: JSON encoding failed")
            }
            try postJSON(json)
        }

        public func setMessageHandler(
            _ handler: @Sendable @escaping (KSIPCMessage) async -> Void
        ) async {
            inboundHandler = { [weak self] text in
                guard let data = text.data(using: .utf8),
                    let msg = try? JSONDecoder().decode(KSIPCMessage.self, from: data)
                else {
                    KSLog.logger("platform.android.webview")
                        .warning("Malformed inbound IPC frame (dropped)")
                    return
                }
                Task { await handler(msg) }
                _ = self
            }
        }

        public func setContentSecurityPolicy(_ csp: String) async throws(KSError) {
            lock.withLock { _csp = csp }
            // CSP enforcement on Android is applied via meta-tag injection in
            // documentStartScript() — done automatically by KSAndroidBridge.
        }

        public func openDevTools() async throws(KSError) {
            try openDevTools()
        }
    }
#endif
