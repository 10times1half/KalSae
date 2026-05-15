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
        // postJob 용으로 백그라운드 스레드에서 접근한다. UI 스레드에서
        // Win32Window.attach()와 동시에 한 번만 설정한다.
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

        /// 가장 최근 `navigate(url:)` 호출의 URL. IPC origin 평가용으로 사용된다.
        /// 향후 WebView2 `ICoreWebView2::get_Source` 바인딩을 추가하면 대체될 수 있다.
        internal private(set) var lastNavigatedURL: String?

        /// `WebView2Host+Operations`에서 navigate가 성공한 직후 호출.
        internal func recordNavigated(url: String) {
            self.lastNavigatedURL = url
        }

        init(label: String) {
            self.label = label
        }

        // MARK: - Synchronous creation with message pumping
        //
        // WebView2의 완료 콜백은 생성 스레드의 STA 메시지 루프로 전달된다.
        // 우리 UI 스레드가 바로 Swift async 실행기가 동작하는 메인 스레드이므로
        // 여기서 continuation을 await하면 메시지 펌프가 멈춰서 콜백이 영원히
        // 도달하지 못한다. 따라서 대기 중인 콜백이 들어올 때까지 로컬 메시지
        // 펌프를 돌린다.

        // C 콜백은 UI 스레드에서 직접 호출되므로,
        // `@MainActor` executor check 트랩이 일어나지 않도록
        // 슬롯을 nonisolated(unsafe)로 선언한다.
        nonisolated(unsafe) private var pendingEnv: KSWV2Env?
        nonisolated(unsafe) private var pendingEnvError: KSError?
        nonisolated(unsafe) private var pendingEnvDone: Bool = false

        nonisolated(unsafe) private var pendingCtrl: KSWV2Controller?
        nonisolated(unsafe) private var pendingCtrlError: KSError?
        nonisolated(unsafe) private var pendingCtrlDone: Bool = false

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

            // Phase A4: legacy `devtools` 인자보다 preferences 가 우선한다.
            // preferences 가 nil 이면 아래 applySettingsBundle 의 기본값
            // (debug=true / release=false) 가 적용된다.
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

            // Phase A4: 선언된 토글 일괄 적용.
            if preferences != nil || envOptions != nil {
                self.capabilityReport = applySettingsBundle(
                    preferences: preferences, windows: envOptions)
            }

            log.info("WebView2 host '\(label)' ready")
        }

        // `setDefaultContextMenusEnabled` / `setAllowExternalDrop` 등은
        // `WebView2Host+Operations.swift` 참고.

        private func createEnvironmentSync(
            userDataFolderOverride: String? = nil,
            envOptions: KSWebViewWindowsOptions? = nil,
            mediaAutoplay: KSWebViewMediaAutoplay? = nil
        ) throws(KSError) -> KSWV2Env {
            pendingEnv = nil
            pendingEnvError = nil
            pendingEnvDone = false

            // 실행 파일 옆 `kalsae.runtime.json`에서 fixed 런타임 / 사용자
            // 데이터 폴더 값을 해석한다.
            let exeDir = WebView2Callbacks.executableDirectory()
            // `swift build` / `swift run` 처럼 EXE 옆에 `WebView2Loader.dll`
            // 이 staging 되지 않은 경우에도 SDK 체크아웃에서 직접 로드할 수
            // 있도록 검색 경로를 prepend 한다. 첫 환경 생성 이전에만 효과가
            // 있으므로 이 시점에서 호출한다.
            KSWebView2LoaderResolver.ensureLoaderDir(executableDir: exeDir)
            let resolved = KSWebView2Runtime.resolve(
                executableDir: exeDir, identifier: WebView2Callbacks.appIdentifier())
            // 윈도우별 userDataPath 오버라이드는 runtime.json 결과보다 우선한다.
            let userDataFolder =
                userDataFolderOverride
                .flatMap { KSWebView2Runtime.expand($0, base: exeDir) }
                ?? resolved.userDataFolder

            // Phase B: mediaAutoplay 로 --autoplay-policy=… 합성.
            // 사용자 인자 앞에 붙여서 사용자 명시값이 있으면 우선하도록
            // 한다(Chromium 은 마지막 값이 이긴다 ㅡ 사용자가 직접 지정한
            // 인자를 보존하기 위해 합성을 먼저, 사용자 인자를 나중에 둔다).
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

        /// `additionalBrowserArguments` 와 `--autoplay-policy=…` 를 합성한다.
        /// 사용자 인자 뒤에 합성 인자를 두면 Chromium 의 last-wins 규칙 상
        /// 사용자 명시값이 효과가 사라지므로, 합성 인자를 먼저 두고 사용자
        /// 인자를 뒤에 둔다.
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

        /// `KSWV2_CreateEnvironment` / `KSWV2_CreateEnvironmentEx` 분기.
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
                return KSWV2_CreateEnvironment(
                    browserPtr, userPtr, selfPtr, ksEnvCompletedThunk)
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
                            browserPtr, userPtr, &opts, selfPtr,
                            ksEnvCompletedThunk)
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
            let hr = KSWV2_CreateController(
                env, UnsafeMutableRawPointer(hwnd), selfPtr,
                ksControllerCompletedThunk)
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
                    // WM_QUIT 수신
                    break
                }
            }
        }

        // C 콜백 thunk에서 호출되는 채움 헬퍼.
        // nonisolated: Swift 6 ABI emits an executor check in the prologue
        // of @MainActor methods even when callers use `unsafeBitCast` to drop
        // the isolation. That check raises STATUS_ILLEGAL_INSTRUCTION
        // (0xC000001D) on the dedicated UI thread because it is not the main
        // actor's thread. Marking these methods nonisolated removes the check
        // entirely; the slots they touch are nonisolated(unsafe) above.
        nonisolated internal func fulfillEnv(hr: Int32, env: KSWV2Env?) {
            if hr >= 0, let env {
                self.pendingEnv = env
            } else {
                self.pendingEnvError = KSError.webview2Failure(
                    "CreateCoreWebView2Environment.callback",
                    hr: hr, code: .platformInitFailed)
            }
            self.pendingEnvDone = true
        }

        nonisolated internal func fulfillController(hr: Int32, ctrl: KSWV2Controller?) {
            if hr >= 0, let ctrl {
                self.pendingCtrl = ctrl
            } else {
                self.pendingCtrlError = KSError.webview2Failure(
                    "CreateCoreWebView2Controller.callback",
                    hr: hr, code: .webviewInitFailed)
            }
            self.pendingCtrlDone = true
        }

        // MARK: - Public operations — see `WebView2Host+Operations.swift`.

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
