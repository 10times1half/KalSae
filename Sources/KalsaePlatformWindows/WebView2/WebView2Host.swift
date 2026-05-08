#if os(Windows)
    internal import WinSDK
    internal import CKalsaeWV2
    internal import Logging
    internal import KalsaeCore
    internal import Foundation

    /// Hosts the WebView2 environment + controller + webview for a single
    /// `Win32Window`.
    ///
    /// All operations must run on the UI thread (the thread that owns the
    /// hosting HWND), hence the `@MainActor` isolation.
    ///
    /// This file contains the lifecycle (init/initialize/dispose) and the
    /// thin op surface (navigate/post/script/CSP/devtools/etc.). Handler
    /// installation lives in `WebView2HostHandlers.swift`; the C-callback
    /// dispatch + retain boxes live in `WebView2Callbacks.swift`.
    @MainActor
    internal final class WebView2Host {
        let label: String
        private let log: Logger = KSLog.logger("platform.windows.webview")

        private var env: KSWV2Env?
        private var controller: KSWV2Controller?
        /// Internal read-only accessor so `WebView2Host+Operations.swift` can
        /// reach the controller without leaking the COM pointer module-wide.
        internal var currentController: KSWV2Controller? { controller }
        /// Internal so the handler-installation extension can verify init
        /// state without surface-leaking the COM pointer.
        internal private(set) var webviewPtr: KSWV2WebView?
        // postJob?⑹쑝濡?諛깃렇?쇱슫???ㅻ젅?쒖뿉???묎렐?쒕떎. UI ?ㅻ젅?쒖뿉??        // Win32Window.attach()? ?숈떆????踰덈쭔 ?ㅼ젙?쒕떎.
        nonisolated(unsafe) internal weak var ownerWindow: Win32Window?

        /// Phase A4: Capability report populated during `initialize` based on
        /// `KSWebViewPreferences` / `KSWebViewWindowsOptions` toggle results.
        /// `nil` until preferences/envOptions are supplied.
        internal private(set) var capabilityReport: KSWebViewCapabilityReport?

        /// Retained handler boxes. Held internal so the handler-installation
        /// extension can release/replace them.
        internal var messageHandlerBox: Unmanaged<MessageHandlerBox>?
        internal var resourceHandlerBox: Unmanaged<ResourceHandlerBox>?
        internal var dropTargetBox: Unmanaged<DropTargetBox>?
        internal var newWindowHandlerBox: Unmanaged<NewWindowHandlerBox>?
        internal var permissionHandlerBox: Unmanaged<PermissionHandlerBox>?
        internal var downloadHandlerBox: Unmanaged<DownloadHandlerBox>?
        internal var serverCertHandlerBox: Unmanaged<ServerCertHandlerBox>?
        internal var basicAuthHandlerBox: Unmanaged<BasicAuthHandlerBox>?
        internal var clientCertHandlerBox: Unmanaged<ClientCertHandlerBox>?

        init(label: String) {
            self.label = label
        }

        // MARK: - Synchronous creation with message pumping
        //
        // WebView2???꾨즺 肄쒕갚???앹꽦 ?ㅻ젅?쒖쓽 STA 硫붿떆吏 ?먮줈 ?꾨떖?쒕떎.
        // ?곕━ UI ?ㅻ젅?쒓? 諛붾줈 Swift async ?ㅽ뻾湲곌? ?숈옉?섎뒗 硫붿씤 ?ㅻ젅?쒖씠誘濡?        // ?닿납?먯꽌 continuation??await?섎㈃ 硫붿떆吏 ?꾪봽媛 援댁＜??肄쒕갚???덈?
        // ?꾩갑?섏? 紐삵븳?? ?곕씪???湲?以묒씤 肄쒕갚???쇱뼱???뚭퉴吏 濡쒖뺄 硫붿떆吏
        // ?꾪봽瑜??뚮┛??

        private var pendingEnv: KSWV2Env?
        private var pendingEnvError: KSError?
        private var pendingEnvDone: Bool = false

        private var pendingCtrl: KSWV2Controller?
        private var pendingCtrlError: KSError?
        private var pendingCtrlDone: Bool = false

        func initialize(hwnd: HWND, devtools: Bool) throws(KSError) {
            try initialize(hwnd: hwnd, devtools: devtools, userDataFolderOverride: nil)
        }

        /// Same as `initialize(hwnd:devtools:)` but lets the caller force a
        /// specific WebView2 user-data folder, taking precedence over
        /// `kalsae.runtime.json`. Used by the per-window
        /// `KSWebViewOptions.userDataPath` setting.
        func initialize(
            hwnd: HWND, devtools: Bool,
            userDataFolderOverride: String?
        ) throws(KSError) {
            try initialize(
                hwnd: hwnd, devtools: devtools,
                userDataFolderOverride: userDataFolderOverride,
                envOptions: nil)
        }

        /// Phase B: extended initializer that also takes Environment-level
        /// options. `envOptions == nil` is equivalent to the legacy path.
        func initialize(
            hwnd: HWND, devtools: Bool,
            userDataFolderOverride: String?,
            envOptions: KSWebViewWindowsOptions?,
            preferences: KSWebViewPreferences? = nil
        ) throws(KSError) {
            let env = try createEnvironmentSync(
                userDataFolderOverride: userDataFolderOverride,
                envOptions: envOptions,
                mediaAutoplay: preferences?.mediaAutoplay)
            self.env = env

            let controller = try createControllerSync(env: env, hwnd: hwnd)
            self.controller = controller

            guard let webview = KSWV2_Controller_GetWebView(controller) else {
                throw KSError(
                    code: .webviewInitFailed,
                    message: "get_CoreWebView2 returned null")
            }
            self.webviewPtr = webview

            // Phase A4: legacy `devtools` ?몄옄蹂대떎 preferences 媛 ?곗꽑?쒕떎.
            // preferences 媛 nil ?대㈃ ?꾨옒 applySettingsBundle ??湲곕낯媛?            // (debug=true / release=false) 媛 ?곸슜?쒕떎.
            if preferences == nil {
                try KSHRESULT(KSWV2_SetDevToolsEnabled(webview, devtools ? 1 : 0))
                    .throwIfFailed(.webviewInitFailed, "put_AreDevToolsEnabled")
            }

            var addScriptHR: Int32 = 0
            KSRuntimeJS.source.withUTF16Pointer { ptr in
                addScriptHR = KSWV2_AddScriptToExecuteOnDocumentCreated(webview, ptr)
            }
            try KSHRESULT(addScriptHR)
                .throwIfFailed(
                    .webviewInitFailed,
                    "AddScriptToExecuteOnDocumentCreated")

            // Phase A4: ?좎뼵???좉? ?쇨큵 ?곸슜.
            if preferences != nil || envOptions != nil {
                self.capabilityReport = applySettingsBundle(
                    preferences: preferences, windows: envOptions)
            }

            log.info("WebView2 host '\(label)' ready")
        }

        // `setDefaultContextMenusEnabled` / `setAllowExternalDrop` ??        // `WebView2Host+Operations.swift` 李멸퀬.

        private func createEnvironmentSync(
            userDataFolderOverride: String? = nil,
            envOptions: KSWebViewWindowsOptions? = nil,
            mediaAutoplay: KSWebViewMediaAutoplay? = nil
        ) throws(KSError) -> KSWV2Env {
            pendingEnv = nil
            pendingEnvError = nil
            pendingEnvDone = false

            // ?ㅽ뻾 ?뚯씪 ??`kalsae.runtime.json`?먯꽌 fixed ?고???/ ?ъ슜??            // ?곗씠???ъ젙??媛믪쓣 ?댁꽍?쒕떎.
            let exeDir = WebView2Callbacks.executableDirectory()
            // `swift build` / `swift run` 泥섎읆 EXE ?놁뿉 `WebView2Loader.dll`
            // ??staging ?섏? ?딆? 寃쎌슦?쇰룄 SDK 泥댄겕?꾩썐?먯꽌 吏곸젒 濡쒕뱶????            // ?덈룄濡?寃??寃쎈줈瑜?prepend ?쒕떎. 泥??섍꼍 ?앹꽦 ?댁쟾?먮쭔 ?④낵媛
            // ?덉쑝誘濡????쒖젏?먯꽌 ?몄텧?쒕떎.
            KSWebView2LoaderResolver.ensureLoaderDir(executableDir: exeDir)
            let resolved = KSWebView2Runtime.resolve(
                executableDir: exeDir, identifier: WebView2Callbacks.appIdentifier())
            // ?덈룄?곕퀎 userDataPath ?ㅻ쾭?쇱씠?쒕뒗 runtime.json 寃곌낵蹂대떎 ?곗꽑?쒕떎.
            let userDataFolder =
                userDataFolderOverride
                .flatMap { KSWebView2Runtime.expand($0, base: exeDir) }
                ?? resolved.userDataFolder

            // Phase B: mediaAutoplay ??--autoplay-policy=???⑹꽦.
            // ?ъ슜???몄옄 ?ㅼ뿉 遺숈뿬 ?ъ슜??紐낆떆媛믪씠 ?덉쑝硫??곗꽑?섏? ?딅룄濡?            // ?쒕떎(Chromium ? 留덉?留?媛믪씠 ?닿릿?????ъ슜?먭? 吏곸젒 吏?뺥븳
            // ?몄옄瑜?蹂댁〈?섍린 ?꾪빐 ?⑹꽦??癒쇱?, ?ъ슜???몄옄瑜??섏쨷???붾떎).
            let mergedArgs = composeArgs(
                userArgs: envOptions?.additionalBrowserArguments,
                mediaAutoplay: mediaAutoplay)

            log.info(
                "WebView2 environment: userDataFolder=\(userDataFolder ?? "<nil>"), browserExecutableFolder=\(resolved.browserExecutableFolder ?? "<default>")"
            )

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let hr: Int32 = withOptionalUTF16(resolved.browserExecutableFolder) { browserPtr in
                withOptionalUTF16(userDataFolder) { userPtr in
                    self.invokeCreateEnvironment(
                        browserPtr: browserPtr,
                        userPtr: userPtr,
                        mergedArgs: mergedArgs,
                        envOptions: envOptions,
                        selfPtr: selfPtr)
                }
            }
            try KSHRESULT(hr).throwIfFailed(
                .platformInitFailed, "CreateCoreWebView2EnvironmentWithOptions")

            pumpMessagesUntil { self.pendingEnvDone }

            if let err = pendingEnvError { throw err }
            guard let env = pendingEnv else {
                throw KSError(
                    code: .platformInitFailed,
                    message: "CreateCoreWebView2Environment: no env returned")
            }
            return env
        }

        /// `additionalBrowserArguments` ? `--autoplay-policy=?? 瑜??⑹꽦?쒕떎.
        /// ?ъ슜???몄옄 ?ㅼ뿉 ?⑹꽦 ?몄옄瑜??먮㈃ Chromium ??last-wins 洹쒖튃 ??        /// ?ъ슜??紐낆떆媛믪씠 ?④낵媛 ?щ씪吏誘濡? ?⑹꽦 ?몄옄瑜?癒쇱? ?먭퀬 ?ъ슜??        /// ?몄옄瑜??ㅼ뿉 ?붾떎.
        private func composeArgs(
            userArgs: String?, mediaAutoplay: KSWebViewMediaAutoplay?
        ) -> String? {
            let synthesized: String?
            switch mediaAutoplay {
            case .never:
                synthesized = "--autoplay-policy=document-user-activation-required"
            case .userGesture:
                synthesized = "--autoplay-policy=user-gesture-required"
            case .always:
                synthesized = "--autoplay-policy=no-user-gesture-required"
            case .none:
                synthesized = nil
            }
            switch (synthesized, userArgs) {
            case (nil, nil): return nil
            case (let s?, nil): return s
            case (nil, let u?): return u
            case (let s?, let u?): return s + " " + u
            }
        }

        /// `KSWV2_CreateEnvironment` / `KSWV2_CreateEnvironmentEx` 遺꾧린.
        private func invokeCreateEnvironment(
            browserPtr: UnsafePointer<UInt16>?,
            userPtr: UnsafePointer<UInt16>?,
            mergedArgs: String?,
            envOptions: KSWebViewWindowsOptions?,
            selfPtr: UnsafeMutableRawPointer
        ) -> Int32 {
            let needsEx =
                mergedArgs != nil
                || envOptions?.language != nil
                || envOptions?.targetCompatibleBrowserVersion != nil
                || envOptions?.allowSingleSignOn != nil
                || envOptions?.exclusiveUserDataFolderAccess != nil
                || envOptions?.trackingPrevention != nil

            if !needsEx {
                return KSWV2_CreateEnvironment(browserPtr, userPtr, selfPtr) {
                    user, hr, env in
                    WebView2Callbacks.receiveEnv(user: user, hr: hr, env: env)
                }
            }

            // tri-state helper
            func tri(_ b: Bool?) -> Int32 {
                guard let b else { return -1 }
                return b ? 1 : 0
            }

            // trackingPrevention enum -> tri-state (off->0, basic/balanced/strict->1).
            let trackingTri: Int32
            switch envOptions?.trackingPrevention {
            case .off: trackingTri = 0
            case .basic, .balanced, .strict: trackingTri = 1
            case .none: trackingTri = -1
            }

            return withOptionalUTF16(mergedArgs) { argsPtr in
                withOptionalUTF16(envOptions?.language) { langPtr in
                    withOptionalUTF16(envOptions?.targetCompatibleBrowserVersion) { tcbvPtr in
                        var opts = KSWV2EnvOptions(
                            additional_browser_arguments: argsPtr,
                            language: langPtr,
                            target_compatible_browser_version: tcbvPtr,
                            allow_single_sign_on: tri(envOptions?.allowSingleSignOn),
                            exclusive_user_data_folder_access:
                                tri(envOptions?.exclusiveUserDataFolderAccess),
                            custom_crash_reporting_enabled: -1,
                            enable_tracking_prevention: trackingTri)
                        return KSWV2_CreateEnvironmentEx(
                            browserPtr, userPtr, &opts, selfPtr
                        ) { user, hr, env in
                            WebView2Callbacks.receiveEnv(user: user, hr: hr, env: env)
                        }
                    }
                }
            }
        }

        private func createControllerSync(
            env: KSWV2Env, hwnd: HWND
        ) throws(KSError) -> KSWV2Controller {
            pendingCtrl = nil
            pendingCtrlError = nil
            pendingCtrlDone = false

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            let hr = KSWV2_CreateController(env, UnsafeMutableRawPointer(hwnd), selfPtr) { user, hr, c in
                WebView2Callbacks.receiveController(user: user, hr: hr, ctrl: c)
            }
            try KSHRESULT(hr).throwIfFailed(
                .webviewInitFailed, "CreateCoreWebView2Controller")

            pumpMessagesUntil { self.pendingCtrlDone }

            if let err = pendingCtrlError { throw err }
            guard let ctrl = pendingCtrl else {
                throw KSError(
                    code: .webviewInitFailed,
                    message: "CreateCoreWebView2Controller: no controller returned")
            }
            return ctrl
        }

        /// Pumps the Win32 message queue until `predicate()` returns true or
        /// `WM_QUIT` is observed. Blocks on `GetMessageW`, so there's no busy
        /// loop.
        private func pumpMessagesUntil(_ predicate: () -> Bool) {
            var msg = MSG()
            while !predicate() {
                if GetMessageW(&msg, nil, 0, 0) {
                    TranslateMessage(&msg)
                    DispatchMessageW(&msg)
                } else {
                    // WM_QUIT ?섏떊
                    break
                }
            }
        }

        // C 肄쒕갚 thunk?먯꽌 ?몄텧?섎뒗 梨꾩? ?ы띁.
        internal func fulfillEnv(hr: Int32, env: KSWV2Env?) {
            if hr >= 0, let env {
                self.pendingEnv = env
            } else {
                self.pendingEnvError = KSError.webview2Failure(
                    "CreateCoreWebView2Environment.callback",
                    hr: hr, code: .platformInitFailed)
            }
            self.pendingEnvDone = true
        }

        internal func fulfillController(hr: Int32, ctrl: KSWV2Controller?) {
            if hr >= 0, let ctrl {
                self.pendingCtrl = ctrl
            } else {
                self.pendingCtrlError = KSError.webview2Failure(
                    "CreateCoreWebView2Controller.callback",
                    hr: hr, code: .webviewInitFailed)
            }
            self.pendingCtrlDone = true
        }

        // MARK: - Public operations ??see `WebView2Host+Operations.swift`.

        // MARK: - Teardown

        func dispose() {
            messageHandlerBox?.release()
            messageHandlerBox = nil
            resourceHandlerBox?.release()
            resourceHandlerBox = nil
            if let owner = ownerWindow, let hwnd = owner.hwnd, dropTargetBox != nil {
                KSWV2_RevokeDropTarget(UnsafeMutableRawPointer(hwnd))
            }
            dropTargetBox?.release()
            dropTargetBox = nil
            newWindowHandlerBox?.release()
            newWindowHandlerBox = nil
            permissionHandlerBox?.release()
            permissionHandlerBox = nil
            downloadHandlerBox?.release()
            downloadHandlerBox = nil
            serverCertHandlerBox?.release()
            serverCertHandlerBox = nil
            basicAuthHandlerBox?.release()
            basicAuthHandlerBox = nil
            clientCertHandlerBox?.release()
            clientCertHandlerBox = nil
            if let controller {
                _ = KSWV2_Controller_Close(controller)
                KSWV2_Controller_Release(controller)
                self.controller = nil
            }
            if let env {
                KSWV2_Env_Release(env)
                self.env = nil
            }
            webviewPtr = nil
        }
    }
#endif
