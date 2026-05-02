#if os(macOS)
    /// `WKUserContentController.addUserScript`瑜??듯빐 紐⑤뱺 ?꾨젅?꾩뿉 二쇱엯?섎뒗 JavaScript.
    /// `KalsaePlatformWindows.KSRuntimeJS`??Windows ?고??꾧낵 ?좎궗?섏?留?    /// ?꾩넚 諛⑹떇???ㅻⅤ怨?(`webkit.messageHandlers.ks.postMessage` ???    /// `window.chrome.webview.postMessage`) ?묐떟怨??대깽?몃? ?꾨떖?섍린 ?꾪빐
    /// ?ㅼ씠?곕툕 痢≪씠 `evaluateJavaScript`濡??몄텧?섎뒗 `__kb_receive` ?⑥닔瑜?    /// ?몄텧?쒕떎.
    internal enum KSRuntimeJS {
        static let source: String = #"""
                        (function () {
              if (window.__KS_) return;

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

              // ?ㅼ씠?곕툕 履쎌뿉?쒕쭔 ?곕뒗 ?? ?섏씠吏 JS媛 ?고??꾩쓣 媛?ν븯湲??대졄?꾨줉
              // ?숆껐??`KB` 媛앹껜 諛뽰뿉 ?묐떎.
              window.__KS_receive = handleInbound;
            })();
            """#
    }
#endif
