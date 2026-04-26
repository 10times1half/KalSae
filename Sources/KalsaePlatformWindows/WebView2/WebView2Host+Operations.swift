#if os(Windows)
internal import WinSDK
internal import CKalsaeWV2
public import KalsaeCore
public import Foundation

// MARK: - WebView2Host public operation surface
//
// `WebView2Host`의 `setBounds` / `navigate` / `postJSON` / `reload` /
// `setVirtualHostMapping` / `addDocumentCreatedScript` 등 PAL 호출자가
// 사용하는 얇은 위임 메서드들을 모은 확장. 라이프사이클(초기화 펌프와
// dispose)은 메인 파일이 그대로 보유한다.

extension WebView2Host {

    func setBounds(x: Int, y: Int, width: Int, height: Int) {
        guard let controller = currentController else { return }
        _ = KSWV2_Controller_SetBounds(
            controller, Int32(x), Int32(y), Int32(width), Int32(height))
    }

    /// Posts a closure onto the UI thread via the owning window's Win32
    /// message queue. This is how background-thread completions (e.g. from
    /// the actor-based command registry) get back to the UI thread without
    /// relying on Swift's main-actor executor being pumped.
    nonisolated func postJob(_ block: @escaping @MainActor () -> Void) {
        ownerWindow?.postJob(block)
    }

    func navigate(url: String) throws(KSError) {
        guard let webview = webviewPtr else {
            throw KSError(code: .webviewInitFailed,
                          message: "WebView not initialized")
        }
        var hr: Int32 = 0
        url.withUTF16Pointer { ptr in
            hr = KSWV2_Navigate(webview, ptr)
        }
        try KSHRESULT(hr).throwIfFailed(.webviewInitFailed, "Navigate(\(url))")
    }

    func postJSON(_ json: String) throws(KSError) {
        guard let webview = webviewPtr else { return }
        var hr: Int32 = 0
        json.withUTF16Pointer { ptr in
            hr = KSWV2_PostWebMessageAsJson(webview, ptr)
        }
        try KSHRESULT(hr).throwIfFailed(.webviewInitFailed, "PostWebMessageAsJson")
    }

    func openDevTools() throws(KSError) {
        guard let webview = webviewPtr else { return }
        try KSHRESULT(KSWV2_OpenDevTools(webview))
            .throwIfFailed(.webviewInitFailed, "OpenDevToolsWindow")
    }

    /// Reloads the current document. Implemented via JavaScript so we
    /// don't need to track the most-recent URL ourselves and so we
    /// don't need a new ICoreWebView2 method binding.
    func reload() {
        guard let webview = webviewPtr else { return }
        let script = "location.reload();"
        script.withUTF16Pointer { ptr in
            _ = KSWV2_ExecuteScript(webview, ptr)
        }
    }

    /// Maps a virtual host name onto a local folder so that
    /// `https://{host}/...` navigations serve assets from that folder.
    /// See `KSWV2_SetVirtualHostNameToFolderMapping`.
    func setVirtualHostMapping(
        host: String, folder: URL, accessKind: Int32 = 2
    ) throws(KSError) {
        guard let webview = webviewPtr else {
            throw KSError(code: .webviewInitFailed,
                          message: "WebView not initialized")
        }
        var hr: Int32 = 0
        host.withUTF16Pointer { hostPtr in
            folder.path.withUTF16Pointer { folderPtr in
                hr = KSWV2_SetVirtualHostNameToFolderMapping(
                    webview, hostPtr, folderPtr, accessKind)
            }
        }
        try KSHRESULT(hr).throwIfFailed(
            .webviewInitFailed,
            "SetVirtualHostNameToFolderMapping(\(host) -> \(folder.path))")
    }

    /// Queues a JS snippet to run at the start of every document. Used by
    /// `KSApp.boot` to inject the runtime bridge (already installed by
    /// `initialize`) and an optional CSP `<meta>` tag.
    func addDocumentCreatedScript(_ script: String) throws(KSError) {
        guard let webview = webviewPtr else {
            throw KSError(code: .webviewInitFailed,
                          message: "WebView not initialized")
        }
        var hr: Int32 = 0
        script.withUTF16Pointer { ptr in
            hr = KSWV2_AddScriptToExecuteOnDocumentCreated(webview, ptr)
        }
        try KSHRESULT(hr).throwIfFailed(
            .webviewInitFailed, "AddScriptToExecuteOnDocumentCreated(csp)")
    }

    /// Enables or disables the WebView2 default context menu. Safe to
    /// call after `initialize`. Best-effort; logs and swallows failures
    /// so security policy never aborts startup.
    func setDefaultContextMenusEnabled(_ enabled: Bool) {
        guard let webview = webviewPtr else { return }
        let hr = KSWV2_SetDefaultContextMenusEnabled(webview, enabled ? 1 : 0)
        if hr < 0 {
            KSLog.logger("platform.windows.webview").warning(
                "put_AreDefaultContextMenusEnabled failed (HRESULT=0x\(String(UInt32(bitPattern: hr), radix: 16)))")
        }
    }

    /// Toggles the controller-level `AllowExternalDrop` flag (Runtime
    /// 1.0.992+). When `false` the page no longer receives OS file
    /// drops and the host's `IDropTarget` sees them instead.
    func setAllowExternalDrop(_ allow: Bool) {
        guard let controller = currentController else { return }
        let hr = KSWV2_Controller_SetAllowExternalDrop(controller, allow ? 1 : 0)
        if hr < 0 {
            KSLog.logger("platform.windows.webview").warning(
                "put_AllowExternalDrop failed (HRESULT=0x\(String(UInt32(bitPattern: hr), radix: 16)))")
        }
    }

    // MARK: - Phase C2 visual / runtime tuning

    /// Sets the controller's default background colour. Pass `a == 0`
    /// (with a transparent host window) to make the WebView see-through.
    /// Best-effort; logs and swallows failures so a missing
    /// `ICoreWebView2Controller2` never blocks startup.
    func setDefaultBackgroundColor(_ color: KSColorRGBA) {
        guard let controller = currentController else { return }
        let a = UInt8(clamping: color.a)
        let r = UInt8(clamping: color.r)
        let g = UInt8(clamping: color.g)
        let b = UInt8(clamping: color.b)
        let hr = KSWV2_Controller_SetDefaultBackgroundColor(controller, a, r, g, b)
        if hr < 0 {
            KSLog.logger("platform.windows.webview").warning(
                "put_DefaultBackgroundColor failed (HRESULT=0x\(String(UInt32(bitPattern: hr), radix: 16)))")
        }
    }

    /// Sets the controller-level zoom factor. Best-effort.
    func setZoomFactor(_ factor: Double) {
        guard let controller = currentController else { return }
        let hr = KSWV2_Controller_SetZoomFactor(controller, factor)
        if hr < 0 {
            KSLog.logger("platform.windows.webview").warning(
                "put_ZoomFactor failed (HRESULT=0x\(String(UInt32(bitPattern: hr), radix: 16)))")
        }
    }

    /// Reads the controller-level zoom factor. Returns `1.0` when the
    /// controller is unavailable or the call fails.
    func getZoomFactor() -> Double {
        guard let controller = currentController else { return 1.0 }
        var v: Double = 1.0
        let hr = KSWV2_Controller_GetZoomFactor(controller, &v)
        return hr < 0 ? 1.0 : v
    }

    /// Toggles `IsPinchZoomEnabled` on the WebView2 settings (Runtime
    /// with `ICoreWebView2Settings5`). Best-effort.
    func setPinchZoomEnabled(_ enabled: Bool) {
        guard let webview = webviewPtr else { return }
        let hr = KSWV2_SetPinchZoomEnabled(webview, enabled ? 1 : 0)
        if hr < 0 {
            KSLog.logger("platform.windows.webview").warning(
                "put_IsPinchZoomEnabled failed (HRESULT=0x\(String(UInt32(bitPattern: hr), radix: 16)))")
        }
    }
}
#endif
