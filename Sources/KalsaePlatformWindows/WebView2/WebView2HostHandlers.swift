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
            case drop = 2
        }

        // MARK: - Web message bridge

        func onMessage(_ handler: @MainActor @escaping (String) -> Void) throws(KSError) {
            guard let webview = webviewPtr else {
                throw KSError(
                    code: .webviewInitFailed,
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
            resolver: KSAssetResolver, csp: String, host: String,
            crossOriginIsolation: Bool = false
        ) throws(KSError) {
            guard let webview = webviewPtr else {
                throw KSError(
                    code: .webviewInitFailed,
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

            // COI 플래그를 헤더 빌더에 전달. 0/non-zero만 의미가 있다.
            _ = KSWV2_SetCrossOriginIsolation(webview, crossOriginIsolation ? 1 : 0)

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
                throw KSError(
                    code: .webviewInitFailed,
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

        // MARK: - 보안 핸들러

        /// 팝업 차단, 권한 거부, 다운로드 알림 핸들러를 한 번에 설치한다.
        ///
        /// - Parameters:
        ///   - allowPopups: `true`이면 `window.open()` 요청이 통과한다.
        ///                  `false`(기본값)이면 즉시 거부되고 선택적으로 외부
        ///                  URL은 OS 기본 브라우저로 라우팅된다.
        ///   - openExternal: 팝업이 차단될 때 URL을 기본 브라우저에서 열기 위한
        ///                   클로저. `nil`이면 단순 거부만 한다.
        ///   - downloadEmit: 다운로드가 시작될 때 호출되어 페이로드를
        ///                   `__ks.webview.downloadStarting` JS 이벤트로
        ///                   라우팅한다. `nil`이면 다운로드 이벤트는 무시된다.
        ///                   v1 정책상 항상 다운로드를 허용(취소하지 않음)한다.
        func installSecurityHandlers(
            allowPopups: Bool,
            openExternal: (@MainActor (String) -> Void)?,
            downloadEmit: (@MainActor (_ url: String, _ mime: String) -> Void)?
        ) throws(KSError) {
            guard let webview = webviewPtr else {
                throw KSError(
                    code: .webviewInitFailed,
                    message: "WebView not initialized")
            }

            // 1. 팝업 / 새 창 요청 핸들러
            newWindowHandlerBox?.release()
            let nwBox = NewWindowHandlerBox { uri in
                if allowPopups { return true }
                // 차단: 기본 브라우저에서 열도록 알림
                openExternal?(uri)
                return false
            }
            let nwUnmanaged = Unmanaged.passRetained(nwBox)
            newWindowHandlerBox = nwUnmanaged
            let nwUser = nwUnmanaged.toOpaque()
            let nwHR = KSWV2_AddNewWindowRequestedHandler(webview, nwUser) { u, uri in
                WebView2Callbacks.dispatchNewWindow(user: u, uri: uri)
            }
            try KSHRESULT(nwHR).throwIfFailed(.webviewInitFailed, "add_NewWindowRequested")

            // 2. 권한 요청 핸들러 (마이크/카메라/지오로케이션 등 기본 거부)
            permissionHandlerBox?.release()
            let permBox = PermissionHandlerBox { _, _ in Int32(0) }  // deny all
            let permUnmanaged = Unmanaged.passRetained(permBox)
            permissionHandlerBox = permUnmanaged
            let permUser = permUnmanaged.toOpaque()
            let permHR = KSWV2_AddPermissionRequestedHandler(webview, permUser) { u, uri, kind in
                WebView2Callbacks.dispatchPermission(user: u, uri: uri, kind: kind)
            }
            try KSHRESULT(permHR).throwIfFailed(.webviewInitFailed, "add_PermissionRequested")

            // 3. 다운로드 시작 핸들러 — 항상 허용하되 JS 측에 알린다.
            downloadHandlerBox?.release()
            let dlBox = DownloadHandlerBox { url, mime in
                downloadEmit?(url, mime)
                return Int32(0)  // allow (취소 안 함)
            }
            let dlUnmanaged = Unmanaged.passRetained(dlBox)
            downloadHandlerBox = dlUnmanaged
            let dlUser = dlUnmanaged.toOpaque()
            let dlHR = KSWV2_AddDownloadStartingHandler(webview, dlUser) { u, url, mime in
                WebView2Callbacks.dispatchDownload(user: u, url: url, mime: mime)
            }
            try KSHRESULT(dlHR).throwIfFailed(.webviewInitFailed, "add_DownloadStarting")

            // 4. TLS/서버 인증서 오류 — deny-secure 기본값. 런타임이
            //    ICoreWebView2_14를 지원하지 않으면 조용히 무시한다.
            serverCertHandlerBox?.release()
            let scBox = ServerCertHandlerBox { Int32(0) }  // 0 = cancel(deny)
            let scUnmanaged = Unmanaged.passRetained(scBox)
            serverCertHandlerBox = scUnmanaged
            let scUser = scUnmanaged.toOpaque()
            let scHR = KSWV2_AddServerCertificateErrorHandler(webview, scUser) { u in
                WebView2Callbacks.dispatchServerCertError(user: u)
            }
            // E_NOINTERFACE: 이전 런타임 버전 — 핸들러 없이 기본 동작(오류 UI 표시).
            if KSHRESULT(scHR).isNotInterface {
                serverCertHandlerBox?.release()
                serverCertHandlerBox = nil
            }

            // 5. HTTP Basic/Digest 인증 — 기본 거부.
            basicAuthHandlerBox?.release()
            let baBox = BasicAuthHandlerBox { _, _ in Int32(0) }  // 0 = cancel
            let baUnmanaged = Unmanaged.passRetained(baBox)
            basicAuthHandlerBox = baUnmanaged
            let baUser = baUnmanaged.toOpaque()
            let baHR = KSWV2_AddBasicAuthenticationHandler(webview, baUser) { u, uri, challenge in
                WebView2Callbacks.dispatchBasicAuth(user: u, uri: uri, challenge: challenge)
            }
            if KSHRESULT(baHR).isNotInterface {
                basicAuthHandlerBox?.release()
                basicAuthHandlerBox = nil
            }

            // 6. 클라이언트 인증서 — 기본 거부.
            clientCertHandlerBox?.release()
            let ccBox = ClientCertHandlerBox { _ in Int32(0) }  // 0 = cancel
            let ccUnmanaged = Unmanaged.passRetained(ccBox)
            clientCertHandlerBox = ccUnmanaged
            let ccUser = ccUnmanaged.toOpaque()
            let ccHR = KSWV2_AddClientCertificateHandler(webview, ccUser) { u, host in
                WebView2Callbacks.dispatchClientCert(user: u, host: host)
            }
            if KSHRESULT(ccHR).isNotInterface {
                clientCertHandlerBox?.release()
                clientCertHandlerBox = nil
            }
        }
    }
#endif
