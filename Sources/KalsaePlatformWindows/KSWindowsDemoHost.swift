#if os(Windows)
internal import WinSDK
internal import Logging
public import KalsaeCore
public import Foundation

// MARK: - Phase 1 demo host

/// Single-window host used by the Phase 1 demo executable.
@MainActor
public final class KSWindowsDemoHost {
    public let registry: KSCommandRegistry
    // `let` + Win32Window의 HWND 필드는 `nonisolated(unsafe)`를 통해
    // 스레드 안전하므로, 백그라운드 스레드도 `postJob`를 호출할 수 있다.
    nonisolated private let window: Win32Window
    private let webview: WebView2Host
    public let bridge: WebView2Bridge
    private let webviewOptions: KSWebViewOptions?
    private let backdropType: KSWindowBackdrop?

    public init(windowConfig: KSWindowConfig,
                registry: KSCommandRegistry) throws(KSError) {
        // WebView2는 CreateCoreWebView2Environment 호출 전에 UI 스레드가
        // STA완다는 조건을 요구한다. 이후 모든 Win32 / WebView2 호출이
        // 안전하도록 가능한 한 이른 시점에 초기화한다.
        try Win32App.shared.ensureCOMInitialized()

        self.registry = registry
        self.window = try Win32Window(config: windowConfig)
        self.webview = WebView2Host(label: windowConfig.label)
        self.bridge = WebView2Bridge(host: webview, registry: registry)
        self.webviewOptions = windowConfig.webview
        self.backdropType = windowConfig.webview?.backdropType
        // WndProc가 Win32 시스템 이벤트(WM_SIZE/WM_MOVE/WM_DPICHANGED 등)를
        // JS로 포워딩할 수 있도록 sink를 설치한다. 웹뷰가 아직 초기화되지
        // 않은 시점의 emit은 PostJSON에서 실패하지만 try?로 무시된다.
        let bridgeRef = self.bridge
        self.window.eventSink = { name, payload in
            try? bridgeRef.emit(event: name, payload: payload)
        }
    }

    public func start(url: String, devtools: Bool) throws(KSError) {
        try ensureWebViewInitialized(devtools: devtools)
        try webview.navigate(url: url)
        if devtools {
            try? webview.openDevTools()
        }
    }

    /// Configures the host to serve `folder` under `https://{host}/...`
    /// before navigation. Call this before `start(url:devtools:)`.
    public func setVirtualHostMapping(
        host: String, folder: URL
    ) throws(KSError) {
        // 가상 호스트 매핑은 웹뷰 생성 이후, 첫 탐색 이전에 설정되어야 한다.
        // `start`가 탐색을 처리하므로, 호출자는 `init`과 `start` 사이에 우리를 호출한다.
        // 그런데 안타깝게도 웹뷰가 아직 초기화되지 않은 상태다 — 저장해둔
        // 매핑 정보를 `start`에서 재적용하는 방식으로 지연한다. 단순함을 위해
        // start를 `prepare`/`navigate`로 나눠 호출자가 webview.initialize 이후에
        // 우리를 호출하도록 요구한다. 지금은 웹뷰가 필요하면 온 디맨드로
        // 초기화한다.
        guard let hwnd = window.hwnd else {
            throw KSError(code: .windowCreationFailed,
                          message: "Window has no HWND")
        }
        try ensureWebViewInitialized(devtools: pendingDevtools)
        try webview.setVirtualHostMapping(host: host, folder: folder)
    }

    /// Installs a script to run at the start of every document. Use this
    /// to inject a CSP `<meta>` tag before any page script can execute.
    public func addDocumentCreatedScript(_ script: String) throws(KSError) {
        guard let hwnd = window.hwnd else {
            throw KSError(code: .windowCreationFailed,
                          message: "Window has no HWND")
        }
        try ensureWebViewInitialized(devtools: pendingDevtools)
        try webview.addDocumentCreatedScript(script)
    }

    /// Registers a synchronous `WebResourceRequested` handler that serves
    /// every request under `https://{host}/*` from `resolver`, attaching
    /// `csp` as `Content-Security-Policy`. Mutually exclusive with
    /// `setVirtualHostMapping` for the same host.
    public func setResourceHandler(
        resolver: KSAssetResolver, csp: String, host: String
    ) throws(KSError) {
        guard let hwnd = window.hwnd else {
            throw KSError(code: .windowCreationFailed,
                          message: "Window has no HWND")
        }
        try ensureWebViewInitialized(devtools: pendingDevtools)
        try webview.setResourceHandler(resolver: resolver, csp: csp, host: host)
    }

    /// Toggles WebView2's default browser-style context menu. Pass
    /// `false` to suppress it (page may still render its own).
    public func setDefaultContextMenusEnabled(_ enabled: Bool) {
        webview.setDefaultContextMenusEnabled(enabled)
    }

    /// Toggles whether the webview accepts external file drops directly.
    /// When `false`, OS file drops fall through to the host window's
    /// drop target (used by Phase 5-3).
    public func setAllowExternalDrop(_ allow: Bool) {
        webview.setAllowExternalDrop(allow)
    }

    /// Installs a host-side `IDropTarget` on the window's HWND that
    /// emits the drop as a `__ks.file.drop` JS event via the bridge.
    /// Call this only after disabling the webview's internal drop with
    /// `setAllowExternalDrop(false)`.
    ///
    /// Payload schema (kept stable; consumed by `__KS_.listen`):
    /// ```json
    /// { "kind": "enter" | "leave" | "drop",
    ///   "x": <screenX>, "y": <screenY>,
    ///   "paths": ["C:\\…", …] }
    /// ```
    public func installFileDropEmitter() throws(KSError) {
        let bridge = self.bridge
        try webview.installFileDropHandler {
            kind, x, y, paths in
            struct Payload: Encodable {
                let kind: String
                let x: Int32
                let y: Int32
                let paths: [String]
            }
            let kindStr: String
            switch kind {
            case .enter: kindStr = "enter"
            case .leave: kindStr = "leave"
            case .drop:  kindStr = "drop"
            }
            let payload = Payload(kind: kindStr, x: x, y: y, paths: paths)
            try? bridge.emit(event: "__ks.file.drop", payload: payload)
            // 아키텍처에서는 경로가 하나라도 있을 때만 enter/drop을 수락해
            // OS가 금지 아이콘 대신 복사 커서를 표시하도록 한다.
            return !paths.isEmpty || kind == .leave
        }
    }

    private var webviewInitialized = false
    private var pendingDevtools = false

    /// Two-phase start: prepare the webview + virtual host, then navigate.
    /// Equivalent to `start(url:devtools:)` when no prepare steps were
    /// performed beforehand.
    public func startPrepared(url: String, devtools: Bool) throws(KSError) {
        pendingDevtools = devtools
        try ensureWebViewInitialized(devtools: devtools)
        try webview.navigate(url: url)
        if devtools { try? webview.openDevTools() }
    }

    /// Ensures the webview is constructed with the right devtools flag,
    /// so that subsequent `setVirtualHostMapping` /
    /// `addDocumentCreatedScript` calls before `startPrepared` don't
    /// latch the wrong setting.
    public func prepare(devtools: Bool) throws(KSError) {
        pendingDevtools = devtools
        try ensureWebViewInitialized(devtools: devtools)
    }

    /// Centralised lazy webview initialisation. Pulls the per-window
    /// `userDataPath` override from `KSWebViewOptions`, then applies the
    /// other Phase C2 visual settings (`transparent`, `disablePinchZoom`,
    /// `zoomFactor`, `backdropType`) immediately after the controller is
    /// available. Idempotent.
    private func ensureWebViewInitialized(devtools: Bool) throws(KSError) {
        if webviewInitialized { return }
        guard let hwnd = window.hwnd else {
            throw KSError(code: .windowCreationFailed,
                          message: "Window has no HWND")
        }
        try webview.initialize(
            hwnd: hwnd,
            devtools: devtools,
            userDataFolderOverride: webviewOptions?.userDataPath)
        window.attach(host: webview)
        try bridge.install()
        applyVisualOptions()
        webviewInitialized = true
    }

    /// Applies `KSWebViewOptions` (transparent / pinch-zoom / zoom
    /// factor) and the optional Win11 system backdrop. All best-effort.
    private func applyVisualOptions() {
        if let backdrop = backdropType {
            window.setSystemBackdrop(backdrop)
        }
        guard let opts = webviewOptions else { return }
        if opts.transparent {
            // 알파 0으로 설정해 WebView2 컨트롤러가 호스트 윈도우
            // 배경을 더이상 가리지 않도록 한다. r/g/b는 0.
            webview.setDefaultBackgroundColor(KSColorRGBA(r: 0, g: 0, b: 0, a: 0))
        }
        if opts.disablePinchZoom {
            webview.setPinchZoomEnabled(false)
        }
        if let z = opts.zoomFactor {
            webview.setZoomFactor(z)
        }
    }

    public func runMessageLoop() -> Int32 {
        Win32App.shared.runMessageLoop()
    }

    public func emit(_ event: String, payload: any Encodable) throws(KSError) {
        try bridge.emit(event: event, payload: payload)
    }

    /// Posts a closure to the UI thread's message queue. Use this from
    /// background threads / Task.detached to safely interact with the
    /// window, webview, or IPC bridge. This exists because Swift's
    /// `MainActor` executor is not integrated with the Win32 message pump.
    nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
        window.postJob(block)
    }

    /// Opaque handle for the demo window, suitable for passing to PAL
    /// backends (`dialogs`, `menus`) as the modal parent.
    public var mainHandle: KSWindowHandle? {
        guard let hwnd = window.hwnd else { return nil }
        let raw = UInt64(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd))))
        return KSWindowHandle(label: window.label, rawValue: raw)
    }

    /// Posts `WM_CLOSE` to the demo window so the standard close path
    /// runs (`WM_DESTROY` → `PostQuitMessage`). Safe to call from any
    /// thread; uses `PostMessageW` which is documented thread-safe.
    nonisolated public func requestQuit() {
        guard let hwnd = window.hwnd else { return }
        _ = PostMessageW(hwnd, UINT(WM_CLOSE), 0, 0)
    }

    /// Registers the built-in `__ks.window.*`, `__ks.shell.*`,
    /// `__ks.clipboard.*`, and `__ks.app.*` commands so the JS-side
    /// `__KS_.window.*` namespaces work out of the box.
    ///
    /// Call this once after constructing the host (and before
    /// `start`/`startPrepared`) so the registrations are in place by the
    /// time the page issues its first invoke.
    public func registerBuiltinCommands(
        platformName: String = "Windows",
        shellScope: KSShellScope = .init(),
        notificationScope: KSNotificationScope = .init()
    ) async {
        let mainLabel = window.label
        let windowsBackend = KSWindowsWindowBackend()
        let shellBackend = KSWindowsShellBackend()
        let clipboardBackend = KSWindowsClipboardBackend()
        let notificationBackend = KSWindowsNotificationBackend()
        let dialogBackend = KSWindowsDialogBackend()

        let mainProvider: @Sendable () -> KSWindowHandle? = { [weak self] in
            // 재생성이 제대로 동작하도록 매번 살아있는 HWND를 조회한다.
            guard let self else { return nil }
            // `self.window`는 비-고립된 상태로 캐프처되므로 백그라운드
            // 스레드에서 `.hwnd`를 읽으면 "오래되었을 수는 있지만 유효한"
            // 포인터가 나온다. 레지스트리만 이를 사용하므로 이 쪽에서 괜찮다.
            guard let hwnd = self.window.hwnd else { return nil }
            let raw = UInt64(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd))))
            return KSWindowHandle(label: mainLabel, rawValue: raw)
        }

        let quit: @Sendable () -> Void = { [weak self] in
            self?.requestQuit()
        }

        await KSBuiltinCommands.register(
            into: registry,
            windows: windowsBackend,
            shell: shellBackend,
            clipboard: clipboardBackend,
            notifications: notificationBackend,
            dialogs: dialogBackend,
            mainWindow: mainProvider,
            quit: quit,
            platformName: platformName,
            shellScope: shellScope,
            notificationScope: notificationScope)

        // Windows 전용: `KSRuntimeJS`의 `app-region: drag` mousedown 히트
        // 테스트에서 사용하는 드래그 영역 헬퍼. 살아있는 HWND를 조회해
        // 윈도우에게 비-클라이언트 이동 루프로 진입하도록 요청한다.
        await registry.register("__ks.window.startDrag") { [weak self] _ in
            await MainActor.run {
                self?.window.startDrag()
            }
            // 빈 성공 페이로드(KSBuiltinCommands.Empty와 동일).
            return .success(Data("{}".utf8))
        }
    }
}
#endif
