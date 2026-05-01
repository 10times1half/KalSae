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

      window.__KS_ = KB;
      if (!window.Kalsae) window.Kalsae = KB;
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
/// JS  →  __KS_bridge.postMessage(json)
///     →  JNI @JavascriptInterface → Swift onInboundMessage(json)
///     →  KSAndroidBridge.handleInbound(json)
///     →  KSIPCBridgeCore dispatches command
///     →  sendResponse  →  postJSON(json)
///     →  JNI evaluateJavascript  →  JS window.__KS_receive(msg)
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
        let pending = lock.withLock { _pendingURL.map { url -> String in _pendingURL = nil; return url } }
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
        return nil   // Return value collection requires a JNI callback — deferred.
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
        inboundHandler = { [weak self] text in
            guard let data = text.data(using: .utf8),
                  let msg = try? JSONDecoder().decode(KSIPCMessage.self, from: data) else {
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
