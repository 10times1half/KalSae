#if os(Linux)
internal import CKalsaeGtk
internal import Logging
public import KalsaeCore
public import Foundation

/// JS runtime injected into every frame at document-start. Identical
/// contract to the Windows/macOS runtimes: `window.__KS_.invoke/listen/emit`.
/// Transport: `window.webkit.messageHandlers.ks.postMessage(obj)` for
/// JS→Swift; `window.__KS_receive(obj)` (called via evaluate_javascript)
/// for Swift→JS.
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

/// Thin Swift wrapper over `CKalsaeGtk`. Owns a `KSGtkHost*` and
/// exposes the small surface that `GtkBridge` needs. Mirrors
/// `WebView2Host` / `WKWebViewHost`.
@MainActor
public final class GtkWebViewHost {
    /// Opaque C host pointer. `nonisolated(unsafe)` because the C
    /// library is thread-affine to the main loop but we need to read
    /// this pointer from nonisolated wrappers (e.g. `postJob`).
    nonisolated(unsafe) fileprivate var hostPtr: OpaquePointer?

    private let log: Logger = KSLog.logger("platform.linux.webview")
    private var inbound: ((String) -> Void)?

    /// Retained box so the C message trampoline can resolve back to
    /// this Swift object via an opaque context pointer.
    private var selfBox: SelfBox?

    public init(appId: String, title: String, width: Int, height: Int) {
        self.hostPtr = ks_gtk_host_new(appId, title,
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

    public func openDevTools() throws(KSError) {
        ks_gtk_host_open_devtools(hostPtr)
    }

    /// Binds the `ks://` scheme handler to serve assets from `root`.
    /// Must be called before `run()` — WebKit only registers scheme
    /// handlers at web-context creation time.
    public func setAssetRoot(_ root: URL) throws(KSError) {
        let resolver = KSAssetResolver(root: root)
        let box = ResolverBox(resolver: resolver)
        // 이전 리졸버를 교체한다. C 쪽에는 단일 슬롯만 존재.
        self.resolverBox?.release()
        let um = Unmanaged.passRetained(box)
        self.resolverBox = um
        ks_gtk_host_set_scheme_resolver(
            hostPtr, linuxSchemeResolverTrampoline, um.toOpaque())
    }

    /// Queues a JS snippet to run at the start of every document.
    public func addDocumentCreatedScript(_ script: String) throws(KSError) {
        ks_gtk_host_add_user_script(hostPtr, script)
    }

    /// Sets the Content-Security-Policy header emitted with every
    /// `ks://` response. Independent of `setAssetRoot`; takes effect
    /// the next time the scheme handler serves an asset.
    public func setResponseCSP(_ csp: String) throws(KSError) {
        ks_gtk_host_set_response_csp(hostPtr, csp)
    }

    private var resolverBox: Unmanaged<ResolverBox>?

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
private final class ResolverBox: @unchecked Sendable {
    let resolver: KSAssetResolver
    init(resolver: KSAssetResolver) { self.resolver = resolver }
}

/// C-side scheme trampoline. Runs on the GTK main thread. Reads the
/// asset via `KSAssetResolver` and returns bytes via `g_malloc`'d
/// buffers the C shim hands to `g_memory_input_stream_new_from_data`.
private let linuxSchemeResolverTrampoline: @convention(c) (
    UnsafePointer<CChar>?,
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32 = { pathPtr, ctxPtr, outData, outLen, outMime in
    guard let pathPtr, let ctxPtr,
          let outData, let outLen else { return -1 }
    let path = String(cString: pathPtr)
    let box = Unmanaged<ResolverBox>.fromOpaque(ctxPtr).takeUnretainedValue()
    do {
        let asset = try box.resolver.resolve(path: path)
        // C 쪽에서 g_free를 호출할 수 있도록 malloc으로 할당한다(glib malloc은
        // 지원되는 모든 플랫폼에서 libc malloc과 상호 운용 가능).
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
private final class SelfBox: @unchecked Sendable {
    weak var owner: GtkWebViewHost?
    init(owner: GtkWebViewHost) { self.owner = owner }
}

/// C-side trampoline. Bridges NUL-terminated JSON from WebKitGTK into
/// the Swift host's `inbound` handler on the main actor.
private let gtkBridgeMessageTrampoline: @convention(c) (
    UnsafePointer<CChar>?, UnsafeMutableRawPointer?
) -> Void = { jsonPtr, ctxPtr in
    guard let jsonPtr, let ctxPtr else { return }
    let text = String(cString: jsonPtr)
    let box = Unmanaged<SelfBox>.fromOpaque(ctxPtr).takeUnretainedValue()
    MainActor.assumeIsolated {
        box.owner?.deliverInbound(text)
    }
}
#endif
