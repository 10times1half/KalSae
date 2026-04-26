#if os(Windows)
internal import WinSDK
internal import CKalsaeWV2
internal import KalsaeCore
internal import Foundation

extension WebView2Host {

    /// Drop-event kinds surfaced by `installFileDropHandler`. Mirrors
    /// `KSWV2DropEventKind` in the C shim.
    public enum DropEventKind: Int32, Sendable {
        case enter = 0
        case leave = 1
        case drop  = 2
    }

    // MARK: - Web message bridge

    func onMessage(_ handler: @MainActor @escaping (String) -> Void) throws(KSError) {
        guard let webview = webviewPtr else {
            throw KSError(code: .webviewInitFailed,
                          message: "WebView not initialized")
        }
        messageHandlerBox?.release()
        let box = MessageHandlerBox(handler: handler)
        let unmanaged = Unmanaged.passRetained(box)
        messageHandlerBox = unmanaged
        let user = unmanaged.toOpaque()
        let hr = KSWV2_AddMessageHandler(webview, user) { u, msg in
            WebView2Callbacks.dispatchMessage(user: u, msg: msg)
        }
        try KSHRESULT(hr).throwIfFailed(
            .webviewInitFailed, "add_WebMessageReceived")
    }

    // MARK: - Web resource interception

    /// Registers a synchronous `WebResourceRequested` handler that serves
    /// every request under `https://{host}/*` from `resolver`, attaching
    /// the given `csp` as a `Content-Security-Policy` response header.
    ///
    /// Replaces `setVirtualHostMapping` when you need header-based CSP.
    /// The two are mutually exclusive for the same host: the virtual host
    /// generates engine-internal responses that `WebResourceRequested`
    /// cannot mutate.
    func setResourceHandler(
        resolver: KSAssetResolver, csp: String, host: String
    ) throws(KSError) {
        guard let webview = webviewPtr else {
            throw KSError(code: .webviewInitFailed,
                          message: "WebView not initialized")
        }
        resourceHandlerBox?.release()
        let box = ResourceHandlerBox(
            resolver: resolver,
            csp: csp,
            hostPrefix: "https://\(host)")
        let unmanaged = Unmanaged.passRetained(box)
        resourceHandlerBox = unmanaged
        let user = unmanaged.toOpaque()

        let hr = KSWV2_AddWebResourceRequestedHandler(webview, user) {
            u, uri, outData, outLen, outCT, outCSP in
            WebView2Callbacks.dispatchResource(
                user: u, uri: uri,
                outData: outData, outLen: outLen,
                outCT: outCT, outCSP: outCSP)
        }
        try KSHRESULT(hr).throwIfFailed(
            .webviewInitFailed, "add_WebResourceRequested")

        let pattern = "https://\(host)/*"
        var hr2: Int32 = 0
        pattern.withUTF16Pointer { ptr in
            hr2 = KSWV2_AddWebResourceRequestedFilter(webview, ptr)
        }
        try KSHRESULT(hr2).throwIfFailed(
            .webviewInitFailed, "AddWebResourceRequestedFilter(\(pattern))")
    }

    // MARK: - Native drop target

    /// Registers an `IDropTarget` on the owning HWND so OS file drops
    /// surface as host-side events. Must be paired with
    /// `setAllowExternalDrop(false)` so WebView2 stops claiming the
    /// drop. The `handler` returns `true` to accept the drop and `false`
    /// to reject; the result is reflected as `DROPEFFECT_COPY` /
    /// `DROPEFFECT_NONE` to the OS drag cursor.
    ///
    /// Calling this replaces any drop target previously installed on the
    /// HWND.
    func installFileDropHandler(
        _ handler: @MainActor @escaping (DropEventKind, Int32, Int32, [String]) -> Bool
    ) throws(KSError) {
        guard let owner = ownerWindow, let hwnd = owner.hwnd else {
            throw KSError(code: .webviewInitFailed,
                          message: "installFileDropHandler requires an attached HWND")
        }
        let oleHR = KSWV2_OleInitializeOnce()
        try KSHRESULT(oleHR).throwIfFailed(.platformInitFailed, "OleInitialize")

        dropTargetBox?.release()
        let box = DropTargetBox(handler: handler)
        let unmanaged = Unmanaged.passRetained(box)
        dropTargetBox = unmanaged
        let user = unmanaged.toOpaque()
        let hr = KSWV2_RegisterDropTarget(
            UnsafeMutableRawPointer(hwnd), user
        ) { u, kind, x, y, paths, count in
            WebView2Callbacks.dispatchDrop(
                user: u, kind: kind, x: x, y: y,
                paths: paths, count: count)
        }
        try KSHRESULT(hr).throwIfFailed(
            .webviewInitFailed, "RegisterDragDrop")
    }
}
#endif
