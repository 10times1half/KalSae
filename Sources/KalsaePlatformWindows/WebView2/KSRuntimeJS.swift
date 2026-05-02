#if os(Windows)
    import Foundation

    /// JavaScript injected via `AddScriptToExecuteOnDocumentCreated` so that every
    /// page loaded into Kalsae's WebView2 has `window.__KS_` available before
    /// any user script runs.
    ///
    /// The runtime mirrors the Tauri v2 surface:
    ///   invoke<T>(cmd, args?): Promise<T>
    ///   listen(event, cb):     () => void        // returns an unsubscriber
    ///   emit(event, payload):  void
    internal enum KSRuntimeJS {
        static let source: String = #"""
                                    (function () {
                          if (window.__KS_) return;

                          // ??????덈뮉 ?癒?쑎 ????? `invoke`??筌뤴뫀諭?reject??
                          // ???紐꾨뮞??곷뮞??筌띾슢諭?? ?紐꾪뀱?癒? `instanceof KalsaeError`??
                          // `.code`嚥??브쑨由??????뉗쓺 ??뺣뼄.
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
                            // 揶쏆빘猿쒐몴?域밸챶?嚥??袁⑸꽊??뺣뼄. WebView2????? JSON??곗쨮 ?袁⑤뼎??랁?
                            // ICoreWebView2WebMessageReceivedEventArgs::get_WebMessageAsJson??
                            // ??쇱뵠?怨뺥닏 筌β돦肉??筌욊낮??遺얜쭆 ?類κ묶?????젻餓Β?? ??由??stringify??롢늺
                            // ??곸㉦ ?紐꾪맜??몃쭆 JSON ?얜챷???곸뵠 ??뤿선甕곌쑬???
                            window.chrome.webview.postMessage(obj);
                          }

                          // ??뤿뻿 筌롫뗄?놅쭪?(Swift -> JS)????由경에??袁⑤뼎??뺣뼄.
                          window.chrome.webview.addEventListener('message', ev => {
                            let msg = ev.data;
                            if (typeof msg === 'string') {
                              try { msg = JSON.parse(msg); } catch (_) { return; }
                            }
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
                          });

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

                          // ?袁⑥삋 ??쇱뿫??쎈읂??곷뮞 ??而?癒?퐣 ?怨뺣뮉 ????
                          function call(name, args) { return KB.invoke(name, args); }

                          // ---- ??덈즲??----
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
                          });

                          // ---- ??----
                          const Shell = Object.freeze({
                            openExternal:     (url) => call('__ks.shell.openExternal', { url: String(url) }),
                            showItemInFolder: (path) => call('__ks.shell.showItemInFolder', { url: String(path) }),
                            moveToTrash:      (path) => call('__ks.shell.moveToTrash', { url: String(path) }),
                          });

                          // ---- ??쇱뵠??곗쨮域?----
                          const Dialog = Object.freeze({
                            // opts: { title?, defaultDirectory?, filters?: [{name, extensions}], allowsMultiple?, window? }
                            // ??{ paths: string[] }   (?띯뫁????paths.length === 0)
                            openFile:     (opts) => call('__ks.dialog.openFile', opts || {}),
                            // opts: { title?, defaultDirectory?, defaultFileName?, filters?, window? }
                            // ??{ path: string|null }
                            saveFile:     (opts) => call('__ks.dialog.saveFile', opts || {}),
                            // opts: { title?, defaultDirectory?, window? } ??{ path: string|null }
                            selectFolder: (opts) => call('__ks.dialog.selectFolder', opts || {}),
                            // opts: { kind: 'info'|'warning'|'error'|'question', title, message, detail?,
                            //         buttons?: 'ok'|'okCancel'|'yesNo'|'yesNoCancel', window? }
                            // ??{ result: 'ok'|'cancel'|'yes'|'no' }
                            message:      (opts) => call('__ks.dialog.message', opts || {}),
                          });

                          // ---- ???계퉪?諭?----
                          const Clipboard = Object.freeze({
                            readText:  () => call('__ks.clipboard.readText'),
                            writeText: (text) => call('__ks.clipboard.writeText', { text: String(text) }),
                            clear:     () => call('__ks.clipboard.clear'),
                            hasFormat: (format) => call('__ks.clipboard.hasFormat', { format: String(format) }),
                          });

                          // ---- ??----
                          const App = Object.freeze({
                            quit:        () => call('__ks.app.quit'),
                            environment: () => call('__ks.environment'),
                            hide:        () => call('__ks.window.hide'),
                            show:        () => call('__ks.window.show'),
                          });

                          // ---- ??源??(`listen`??癰귢쑴臾? ----
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

                          // ---- 嚥≪뮄??(__ks.log?????퉸 ??쇱뵠?怨뺥닏 嚥≪뮄?뉑에???깆뒭?? ----
                          function logAt(level) {
                            return function (...args) {
                              const text = args.map(a =>
                                (typeof a === 'string') ? a
                                  : (a instanceof Error) ? (a.stack || a.message)
                                  : (() => { try { return JSON.stringify(a); } catch (_) { return String(a); } })()
                              ).join(' ');
                              // ??뺣즲夷??由??? 嚥≪뮄?????륁뵠筌왖???類?럡??곴퐣???????嚥??癒?쑎???얜똻???뺣뼄.
                              try { call('__ks.log', { level, message: text }).catch(() => {}); }
                              catch (_) { /* registry may not be wired yet */ }
                              // devtools??域밸챶?嚥?癰귣똻??袁⑥쨯 ?꾩꼷??癒?즲 沃섎챶??쭕怨밸립??
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
                          // ?紐꾩벥 癰귢쑴臾?
                          if (!window.Kalsae) window.Kalsae = Root;

                          // ---- ??뺤삋域??怨몃열 ??딅뱜 ???뮞??(?袁⑥쟿?袁ⓥ봺????덈즲?怨쀬뒠) ----
                          //
                          // mousedown ???怨몄벥 鈺곌퀣湲?筌ｋ똻???椰꾧퀣??????ゅ첎?筌?`app-region`(?癒?뮉
                          // `--ks-app-region`) ?④쑴沅??????깆뵠 筌?`drag`???癒?꺖??筌≪뼚?앾쭖?
                          // `__ks.window.startDrag`嚥???쇱뵠?怨뺥닏 ???????곷섧????뺤삋域밸챶? 揶쏆뮇???뺣뼄.
                          // `no-drag` 揶쏅?? 鈺곌퀣湲???쀬돳??筌앸맩??餓λ쵎???뽱룖 ??뺤삋域?揶쎛?館釉?獄????癒?뻼??
                          // ??뺤삋域밸챶? ??쇰뻻 ??곸젫??????덈즲嚥???뺣뼄 (Electron / Chromium ???嚥?.
                          //
                          // ??뤿뻼燁???용뮉 ??곗뺘 ?λ뜃由??????????춸 ??덉삂??뺣뼄. ????낆젾/筌띻낱寃?
                          // contenteditable????뽰뇚??뤿연 ??뺤삋域밸㈇? ??곗뺘 UI ??뽯뮞筌ｌ꼶? 獄쎻뫚鍮??? ??낅즲嚥???뺣뼄.
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
                        })();
            """#
    }
#endif
