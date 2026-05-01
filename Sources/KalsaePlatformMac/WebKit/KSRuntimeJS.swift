#if os(macOS)
/// `WKUserContentController.addUserScript`를 통해 모든 프레임에 주입되는 JavaScript.
/// `KalsaePlatformWindows.KSRuntimeJS`의 Windows 런타임과 유사하지만
/// 전송 방식이 다르고 (`webkit.messageHandlers.ks.postMessage` 대신
/// `window.chrome.webview.postMessage`) 응답과 이벤트를 전달하기 위해
/// 네이티브 측이 `evaluateJavaScript`로 호출하는 `__kb_receive` 함수를
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

      // 네이티브 쪽에서만 쓰는 훅. 페이지 JS가 런타임을 가장하기 어렵도록
      // 동결된 `KB` 객체 밖에 둑다.
      window.__KS_receive = handleInbound;
    })();
    """#
}
#endif
