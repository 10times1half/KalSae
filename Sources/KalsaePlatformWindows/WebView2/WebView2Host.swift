#if os(Windows)
internal import WinSDK
internal import CKalsaeWV2
internal import Logging
public import KalsaeCore
public import Foundation

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
    // postJob용으로 백그라운드 스레드에서 접근한다. UI 스레드에서
    // Win32Window.attach()와 동시에 한 번만 설정된다.
    nonisolated(unsafe) internal weak var ownerWindow: Win32Window?

    /// Retained handler boxes. Held internal so the handler-installation
    /// extension can release/replace them.
    internal var messageHandlerBox: Unmanaged<MessageHandlerBox>?
    internal var resourceHandlerBox: Unmanaged<ResourceHandlerBox>?
    internal var dropTargetBox: Unmanaged<DropTargetBox>?

    init(label: String) {
        self.label = label
    }

    // MARK: - Synchronous creation with message pumping
    //
    // WebView2는 완료 콜백을 생성 스레드의 STA 메시지 큐로 전달한다.
    // 우리 UI 스레드가 바로 Swift async 실행기가 동작하는 메인 스레드이므로
    // 이곳에서 continuation을 await하면 메시지 펄프가 굴주려 콜백이 절대
    // 도착하지 못한다. 따라서 대기 중인 콜백이 일어날 때까지 로컬 메시지
    // 펄프를 돌린다.

    private var pendingEnv: KSWV2Env?
    private var pendingEnvError: KSError?
    private var pendingEnvDone: Bool = false

    private var pendingCtrl: KSWV2Controller?
    private var pendingCtrlError: KSError?
    private var pendingCtrlDone: Bool = false

    func initialize(hwnd: HWND, devtools: Bool) throws(KSError) {
        let env = try createEnvironmentSync()
        self.env = env

        let controller = try createControllerSync(env: env, hwnd: hwnd)
        self.controller = controller

        guard let webview = KSWV2_Controller_GetWebView(controller) else {
            throw KSError(code: .webviewInitFailed,
                          message: "get_CoreWebView2 returned null")
        }
        self.webviewPtr = webview

        try KSHRESULT(KSWV2_SetDevToolsEnabled(webview, devtools ? 1 : 0))
            .throwIfFailed(.webviewInitFailed, "put_AreDevToolsEnabled")

        var addScriptHR: Int32 = 0
        KSRuntimeJS.source.withUTF16Pointer { ptr in
            addScriptHR = KSWV2_AddScriptToExecuteOnDocumentCreated(webview, ptr)
        }
        try KSHRESULT(addScriptHR)
            .throwIfFailed(.webviewInitFailed,
                           "AddScriptToExecuteOnDocumentCreated")

        log.info("WebView2 host '\(label)' ready")
    }

    // `setDefaultContextMenusEnabled` / `setAllowExternalDrop` —
    // `WebView2Host+Operations.swift` 참고.

    private func createEnvironmentSync() throws(KSError) -> KSWV2Env {
        pendingEnv = nil
        pendingEnvError = nil
        pendingEnvDone = false

        // 실행 파일 옆 `kalsae.runtime.json`에서 fixed 런타임 / 사용자
        // 데이터 재정의 값을 해석한다.
        let exeDir = WebView2Callbacks.executableDirectory()
        let resolved = KSWebView2Runtime.resolve(
            executableDir: exeDir, identifier: WebView2Callbacks.appIdentifier())

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let hr: Int32 = withOptionalUTF16(resolved.browserExecutableFolder) { browserPtr in
            withOptionalUTF16(resolved.userDataFolder) { userPtr in
                KSWV2_CreateEnvironment(browserPtr, userPtr, selfPtr) { user, hr, env in
                    WebView2Callbacks.receiveEnv(user: user, hr: hr, env: env)
                }
            }
        }
        try KSHRESULT(hr).throwIfFailed(
            .platformInitFailed, "CreateCoreWebView2EnvironmentWithOptions")

        pumpMessagesUntil { self.pendingEnvDone }

        if let err = pendingEnvError { throw err }
        guard let env = pendingEnv else {
            throw KSError(code: .platformInitFailed,
                          message: "CreateCoreWebView2Environment: no env returned")
        }
        return env
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
            throw KSError(code: .webviewInitFailed,
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

    // C 콜백 thunk에서 호출하는 채움 헬퍼.
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
