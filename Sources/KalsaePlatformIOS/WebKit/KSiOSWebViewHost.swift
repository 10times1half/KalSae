#if os(iOS)
    internal import UIKit
    internal import WebKit
    public import KalsaeCore
    public import Foundation

    // MARK: - iOS 런타임 JS

    /// iOS WebView에 주입되는 브리지 JavaScript. macOS의 `KSRuntimeJS`와
    /// 동일한 역할을 하지만 `webkit.messageHandlers` API를 통해 iOS와 통신한다.
    private enum KSiOSRuntimeJS {
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
                              console.error('[KS] postMessage failed', e);
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

                          // ---- 보안 비밀(자격증명) ----
                          const Secret = (() => {
                            function _toBytes(secret) {
                              if (secret == null) return new Uint8Array(0);
                              if (typeof secret === 'string') return new TextEncoder().encode(secret);
                              if (secret instanceof Uint8Array) return secret;
                              if (secret instanceof ArrayBuffer) return new Uint8Array(secret);
                              if (ArrayBuffer.isView(secret)) return new Uint8Array(secret.buffer, secret.byteOffset, secret.byteLength);
                              throw new TypeError('secret must be string | Uint8Array | ArrayBuffer');
                            }
                            function _b64encode(bytes) {
                              let bin = '';
                              for (let i = 0; i < bytes.byteLength; i++) bin += String.fromCharCode(bytes[i]);
                              return btoa(bin);
                            }
                            function _b64decode(b64) {
                              const bin = atob(b64);
                              const u8 = new Uint8Array(bin.length);
                              for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
                              return u8;
                            }
                            return Object.freeze({
                              set: (service, account, secret) => call('__ks.secret.set', {
                                service: String(service), account: String(account),
                                secret: _b64encode(_toBytes(secret))
                              }),
                              get: async (service, account) => {
                                const r = await call('__ks.secret.get', { service: String(service), account: String(account) });
                                if (!r || !r.secret) return null;
                                return _b64decode(r.secret);
                              },
                              getString: async (service, account) => {
                                const r = await call('__ks.secret.get', { service: String(service), account: String(account) });
                                if (!r || !r.secret) return null;
                                return new TextDecoder().decode(_b64decode(r.secret));
                              },
                              delete: (service, account) => call('__ks.secret.delete', { service: String(service), account: String(account) }),
                              list:   (service) => call('__ks.secret.list', { service: String(service) }),
                            });
                          })();

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
                            secret: Secret,
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

    // MARK: - iOS WebView 호스트
    @MainActor
    public final class KSiOSWebViewHost {
        internal let webView: WKWebView
        private let userContentController: WKUserContentController
        private let messageHandler: KSiOSScriptMessageHandler
        private let schemeHandler: KSiOSSchemeHandler
        private var inbound: ((String) -> Void)?
        nonisolated(unsafe) private static let _sharedEncoder = JSONEncoder()

        public init(label: String) {
            let ucc = WKUserContentController()
            self.userContentController = ucc
            self.messageHandler = KSiOSScriptMessageHandler()
            self.schemeHandler = KSiOSSchemeHandler()

            let config = WKWebViewConfiguration()
            config.userContentController = ucc
            config.setURLSchemeHandler(schemeHandler, forURLScheme: "ks")

            let runtimeScript = WKUserScript(
                source: KSiOSRuntimeJS.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            ucc.addUserScript(runtimeScript)

            self.webView = WKWebView(frame: .zero, configuration: config)
            self.webView.scrollView.bounces = false
            // RFC-008 §4.2: devtools-off-by-default. iOS 16.4+ adds
            // `isInspectable`; default is false but we set it explicitly so a
            // future SDK default flip cannot regress production builds.
            if #available(iOS 16.4, *) {
                self.webView.isInspectable = false
            }

            messageHandler.onMessage = { [weak self] text in
                self?.inbound?(text)
            }
            ucc.add(messageHandler, name: "ks")

            KSLog.logger("platform.ios.webview").info("WKWebView created (label=\(label))")
        }

        public func onMessage(_ handler: @escaping @MainActor (String) -> Void) throws(KSError) {
            self.inbound = handler
        }

        /// 현재 WKWebView의 frame bounds. RFC-008 #2.9 — 윈도우 상태 영속화의
        /// 캡처 소스로 사용된다. iOS는 사용자가 조작 가능한 윈도우 위치/크기 개념이
        /// 없어 화면 크기와 거의 동일한 값을 반환한다.
        public var currentBounds: CGRect { webView.bounds }

        public func navigate(url: String) throws(KSError) {
            guard let u = URL(string: url) else {
                throw KSError(code: .webviewInitFailed, message: "Invalid URL: \(url)")
            }
            if u.isFileURL {
                webView.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: u))
            }
        }

        public func postJSON(_ json: String) throws(KSError) {
            // RFC-005 §4.8: U+2028/U+2029 이스케이프
            let safe =
                json
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            let script = "window.__KS_receive(\(safe));"
            webView.evaluateJavaScript(script) { _, err in
                if let err {
                    KSLog.logger("platform.ios.webview")
                        .warning("evaluateJavaScript failed: \(err)")
                }
            }
        }

        public func setAssetRoot(_ root: URL) throws(KSError) {
            schemeHandler.resolver = KSAssetResolver(root: root)
        }

        public func addDocumentCreatedScript(_ script: String) throws(KSError) {
            let us = WKUserScript(
                source: script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            userContentController.addUserScript(us)
        }

        // MARK: - RFC-008 §4.2 보안 핸들러 (macOS Phase 2와 동일 패턴)

        private var securityDelegate: KSiOSSecurityDelegate?
        private var navigationDelegate: KSiOSNavigationDelegate?
        private var contextMenuScriptInstalled = false
        private var externalDropScriptInstalled = false

        /// 우클릭/롱프레스 컨텍스트 메뉴 비활성화. iOS에서는 텍스트 선택 메뉴와
        /// 링크 롱프레스가 해당된다.
        public func setDefaultContextMenusEnabled(_ enabled: Bool) {
            guard !enabled else { return }
            if contextMenuScriptInstalled { return }
            contextMenuScriptInstalled = true
            let us = WKUserScript(
                source: KSiOSSecurityScripts.disableContextMenu,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            userContentController.addUserScript(us)
        }

        /// 외부 파일 드롭 비활성화. iOS는 데스크톱 드래그&드롭이 제한적이지만
        /// iPadOS Drop interaction은 가능하므로 JS 차단을 적용한다.
        public func setAllowExternalDrop(_ allow: Bool) {
            guard !allow else { return }
            if externalDropScriptInstalled { return }
            externalDropScriptInstalled = true
            let us = WKUserScript(
                source: KSiOSSecurityScripts.disableExternalDrop,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            userContentController.addUserScript(us)
        }

        /// 팝업 차단 + 외부 URL 라우팅 + 권한 거부.
        public func installSecurityHandlers(
            allowPopups: Bool,
            openExternal: (@MainActor (String) -> Void)?
        ) throws(KSError) {
            let sec = securityDelegate ?? KSiOSSecurityDelegate()
            sec.allowPopups = allowPopups
            sec.openExternal = openExternal
            self.securityDelegate = sec
            self.webView.uiDelegate = sec

            let nav = navigationDelegate ?? KSiOSNavigationDelegate()
            nav.openExternal = openExternal
            self.navigationDelegate = nav
            self.webView.navigationDelegate = nav
        }

        /// 파일 드롭 emitter — iOS WKWebView는 외부 가로채기 API가 없어 stub.
        public func installFileDropEmitter() throws(KSError) {
            KSLog.logger("platform.ios.webview").warning(
                "iOS installFileDropEmitter() is a stub — UIDropInteraction 통합은 후속 작업.")
        }

        public func openDevTools() throws(KSError) {
            // iOS에서는 Web Inspector를 프로그래밍 방식으로 열 수 없음.
            // macOS는 Safari + Safari Web Inspector 설정 필요. 여기서는 no-op.
        }
    }

    // MARK: - KSWebViewBackend 적합
    extension KSiOSWebViewHost: KSWebViewBackend {
        public func load(url: URL) async throws(KSError) {
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
        }

        @discardableResult
        public func evaluateJavaScript(_ source: String) async throws(KSError) -> Data? {
            do {
                return try await withCheckedThrowingContinuation {
                    (cont: CheckedContinuation<Data?, any Error>) in
                    webView.evaluateJavaScript(source) { result, error in
                        if let error {
                            cont.resume(throwing: error)
                            return
                        }
                        if let result, !(result is NSNull),
                            let data = try? JSONSerialization.data(withJSONObject: result)
                        {
                            cont.resume(returning: data)
                        } else {
                            cont.resume(returning: nil)
                        }
                    }
                }
            } catch {
                throw KSError(code: .internal, message: "evaluateJavaScript: \(error)")
            }
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
            self.inbound = { [weak self] text in
                guard let data = text.data(using: .utf8),
                    let msg = try? JSONDecoder().decode(KSIPCMessage.self, from: data)
                else { return }
                Task { await handler(msg) }
                _ = self
            }
        }

        public func setContentSecurityPolicy(_ csp: String) async throws(KSError) {
            schemeHandler.csp = csp
        }

        public func setCrossOriginIsolation(_ enabled: Bool) {
            schemeHandler.crossOriginIsolation = enabled
        }

        public func openDevTools() async throws(KSError) {
            // iOS에서는 Web Inspector를 프로그래밍 방식으로 열 수 없음.
        }
    }

    // MARK: - ks:// 스킴 핸들러
    @MainActor
    internal final class KSiOSSchemeHandler: NSObject, WKURLSchemeHandler {
        var resolver: KSAssetResolver?
        var csp: String = KSSecurityConfig.defaultCSP
        var crossOriginIsolation: Bool = false

        nonisolated func webView(
            _ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask
        ) {
            MainActor.assumeIsolated { self.startTask(urlSchemeTask) }
        }

        nonisolated func webView(
            _ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask
        ) {}

        private func startTask(_ task: any WKURLSchemeTask) {
            guard let url = task.request.url, let resolver else {
                task.didFailWithError(
                    NSError(
                        domain: "Kalsae", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "no resolver bound"]))
                return
            }
            do {
                let asset = try resolver.resolve(path: url.path)
                var headers: [String: String] = [
                    "Content-Type": asset.mimeType,
                    "Content-Length": String(asset.data.count),
                    "Content-Security-Policy": csp,
                    // RFC-008 §4.2: macOS / Linux 와 동일한 보안 헤더 표면.
                    "X-Content-Type-Options": "nosniff",
                    "Referrer-Policy": "no-referrer",
                ]
                if crossOriginIsolation {
                    headers["Cross-Origin-Opener-Policy"] = "same-origin"
                    headers["Cross-Origin-Embedder-Policy"] = "require-corp"
                    headers["Cross-Origin-Resource-Policy"] = "same-origin"
                }
                guard
                    let response = HTTPURLResponse(
                        url: url, statusCode: 200,
                        httpVersion: "HTTP/1.1", headerFields: headers)
                else {
                    task.didFailWithError(NSError(domain: "Kalsae", code: 500))
                    return
                }
                task.didReceive(response)
                task.didReceive(asset.data)
                task.didFinish()
            } catch {
                task.didFailWithError(
                    NSError(
                        domain: "Kalsae", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: String(describing: error)]))
            }
        }
    }

    // MARK: - 스크립트 메시지 핸들러
    @MainActor
    internal final class KSiOSScriptMessageHandler: NSObject, WKScriptMessageHandler {
        internal var onMessage: (@MainActor (String) -> Void)?

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            let body = message.body
            MainActor.assumeIsolated {
                let text: String
                if let s = body as? String {
                    text = s
                } else if JSONSerialization.isValidJSONObject(body) {
                    if let data = try? JSONSerialization.data(withJSONObject: body),
                        let s = String(data: data, encoding: .utf8)
                    {
                        text = s
                    } else {
                        return
                    }
                } else {
                    return
                }
                self.onMessage?(text)
            }
        }
    }
#endif
