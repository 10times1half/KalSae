#if os(Android)
import Foundation

// MARK: - C callback function pointer types

/// Evaluates a JavaScript string in the active Android WebView.
/// Kotlin provides this by bridging `WebView.evaluateJavascript(js, null)`.
typealias KSJNIEvaluateJS = @convention(c) (UnsafePointer<CChar>) -> Void

/// Loads a URL in the active Android WebView.
/// Kotlin provides this by bridging `WebView.loadUrl(url)`.
typealias KSJNILoadURL = @convention(c) (UnsafePointer<CChar>) -> Void

// MARK: - Global C callback storage

// nonisolated(unsafe): every read/write is guarded by _hooksLock.
let _hooksLock = NSLock()
nonisolated(unsafe) var _jniEvaluateJS: KSJNIEvaluateJS? = nil
nonisolated(unsafe) var _jniLoadURL: KSJNILoadURL? = nil

// MARK: - Hook wiring

/// Wires the registered C function pointers into a WebView host's Swift
/// injectable closures. Must be called on the MainActor after startup.
@MainActor
func wireJNIHooks(into webViewHost: KSAndroidWebViewHost) {
    webViewHost.onEvaluateJS = { js in
        guard let fn = _hooksLock.withLock({ _jniEvaluateJS }) else { return }
        js.withCString { fn($0) }
    }
    webViewHost.onLoadURL = { url in
        guard let fn = _hooksLock.withLock({ _jniLoadURL }) else { return }
        url.withCString { fn($0) }
    }
}
#endif
