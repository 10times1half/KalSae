#if os(Android)
    import Foundation

    // MARK: - C callback function pointer types

    /// Evaluates a JavaScript string in the active Android WebView.
    /// Kotlin provides this by bridging `WebView.evaluateJavascript(js, null)`.
    typealias KSJNIEvaluateJS = @convention(c) (UnsafePointer<CChar>) -> Void

    /// Loads a URL in the active Android WebView.
    /// Kotlin provides this by bridging `WebView.loadUrl(url)`.
    typealias KSJNILoadURL = @convention(c) (UnsafePointer<CChar>) -> Void

    // RFC-007 Phase 4 (scaffolding) — Dialog/Menu JNI hooks.
    // Storage and registration entry points only; default Swift handlers in
    // KSAndroidDialogBackend / KSAndroidMenuBackend are NOT auto-installed yet.
    // A future session will add the request-id ↔ continuation bridge that lets
    // Kotlin post results back via KS_android_on_dialog_result(...).

    /// Presents a native `AlertDialog` from Kotlin. Kotlin must post the user's
    /// choice back via `KS_android_on_dialog_result(requestId, resultJson)`.
    /// Signature: `(requestId, optionsJsonCStr) -> Void`.
    typealias KSJNIShowAlert = @convention(c) (Int32, UnsafePointer<CChar>) -> Void

    /// Launches an `ActivityResultLauncher` for opening files. Signature:
    /// `(requestId, optionsJsonCStr) -> Void`.
    typealias KSJNIPickFile = @convention(c) (Int32, UnsafePointer<CChar>) -> Void

    /// Launches an `ActivityResultLauncher` for saving a file. Signature:
    /// `(requestId, optionsJsonCStr) -> Void`.
    typealias KSJNISaveFile = @convention(c) (Int32, UnsafePointer<CChar>) -> Void

    /// Launches an `ActivityResultLauncher` for selecting a folder. Signature:
    /// `(requestId, optionsJsonCStr) -> Void`.
    typealias KSJNISelectFolder = @convention(c) (Int32, UnsafePointer<CChar>) -> Void

    /// Shows a `PopupMenu` anchored to the active WebView at the given point.
    /// Signature: `(requestId, menuJsonCStr, x, y) -> Void`.
    typealias KSJNIShowContextMenu = @convention(c) (Int32, UnsafePointer<CChar>, Int32, Int32) -> Void

    // MARK: - Global C callback storage

    // nonisolated(unsafe): every read/write is guarded by _hooksLock.
    let _hooksLock = NSLock()
    nonisolated(unsafe) var _jniEvaluateJS: KSJNIEvaluateJS? = nil
    nonisolated(unsafe) var _jniLoadURL: KSJNILoadURL? = nil
    nonisolated(unsafe) var _jniShowAlert: KSJNIShowAlert? = nil
    nonisolated(unsafe) var _jniPickFile: KSJNIPickFile? = nil
    nonisolated(unsafe) var _jniSaveFile: KSJNISaveFile? = nil
    nonisolated(unsafe) var _jniSelectFolder: KSJNISelectFolder? = nil
    nonisolated(unsafe) var _jniShowContextMenu: KSJNIShowContextMenu? = nil

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
