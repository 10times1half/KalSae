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

              // 플랫폼 측에 전달되는 모든 JS가 이 함수를 사용할 수 있다고 가정하므로
              // `KB` 객체 생성 후에 배치한다.
              window.__KS_receive = handleInbound;
            })();
            """#
    }
#endif
