#if os(macOS)
    /// `WKUserContentController.addUserScript`를 통해 모든 프레임에 주입되는 JavaScript.
    /// `KalsaePlatformWindows.KSRuntimeJS`와 Windows 버전과 구조가 같지만
    /// 통신 방식만 다르다(`webkit.messageHandlers.ks.postMessage` 대신
    /// `window.chrome.webview.postMessage`). 플랫폼 간 차이를
    /// 추상화하기 위해 `evaluateJavaScript`로 전달하는 `__kb_receive` 함수를
    /// 노출한다.
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

              const pending = new Map();     // id -> {resolve, reject}
              const listeners = new Map();   // event -> Set<fn>
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

              // 플랫폼 측에 전달되는 모든 JS가 이 함수를 사용할 수 있다고 가정하므로
              // `KB` 객체 생성 후에 배치한다.
              window.__KS_receive = handleInbound;
            })();
            """#
    }
#endif
