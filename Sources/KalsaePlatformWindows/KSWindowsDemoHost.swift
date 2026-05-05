#if os(Windows)
    internal import WinSDK
    internal import Logging
    public import KalsaeCore
    public import Foundation

    // MARK: - 데모 호스트

    /// 데모 실행 파일에서 사용하는 윈도우 호스트.
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
        private let windowTransparent: Bool

        public init(
            windowConfig: KSWindowConfig,
            registry: KSCommandRegistry,
            restoredState: KSPersistedWindowState? = nil
        ) throws(KSError) {
            // WebView2는 CreateCoreWebView2Environment 호출 전에 UI 스레드가
            // STA완다는 조건을 요구한다. 이후 모든 Win32 / WebView2 호출이
            // 안전하도록 가능한 한 이른 시점에 초기화한다.
            try Win32App.shared.ensureCOMInitialized()

            self.registry = registry
            // Mica / Acrylic / Tabbed 백드롭은 윈도우가 투명하지 않으면 보이지
            // 않는다. 사용자가 `transparent`를 명시적으로 지정하지 않은 채
            // 시각적 backdrop 만 요청한 경우 자동으로 `transparent=true` 로
            // 승격하고 1회 경고 로그를 남긴다 (`auto`/`none`은 시각 효과가
            // 없으므로 승격 대상이 아님).
            var effectiveConfig = windowConfig
            if !effectiveConfig.transparent,
                let bd = effectiveConfig.webview?.backdropType,
                bd == .mica || bd == .acrylic || bd == .tabbed
            {
                effectiveConfig.transparent = true
                Self.warnBackdropAutoTransparentOnce(backdrop: bd)
            }
            self.window = try Win32Window(
                config: effectiveConfig,
                restoredState: restoredState)
            self.webview = WebView2Host(label: effectiveConfig.label)
            self.bridge = WebView2Bridge(host: webview, registry: registry, windowLabel: effectiveConfig.label)
            self.webviewOptions = effectiveConfig.webview
            self.backdropType = effectiveConfig.webview?.backdropType
            self.windowTransparent = effectiveConfig.transparent
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

        /// 탐색 전에 `https://{host}/...` 하위에서 `folder`를 제공하도록
        /// 호스트를 구성한다. `start(url:devtools:)` 호출 전에 사용한다.
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
            guard window.hwnd != nil else {
                throw KSError(
                    code: .windowCreationFailed,
                    message: "Window has no HWND")
            }
            try ensureWebViewInitialized(devtools: pendingDevtools)
            try webview.setVirtualHostMapping(host: host, folder: folder)
        }

        /// 모든 문서 시작 시 실행될 스크립트를 설치한다.
        /// 페이지 스크립트가 실행되기 전에 CSP `<meta>` 태그를 주입할 때 사용한다.
        public func addDocumentCreatedScript(_ script: String) throws(KSError) {
            guard window.hwnd != nil else {
                throw KSError(
                    code: .windowCreationFailed,
                    message: "Window has no HWND")
            }
            try ensureWebViewInitialized(devtools: pendingDevtools)
            try webview.addDocumentCreatedScript(script)
        }

        /// `resolver`에서 `https://{host}/*` 하위의 모든 요청을 처리하는
        /// 동기 `WebResourceRequested` 핸들러를 등록하고 `csp`를
        /// `Content-Security-Policy`로 쳊부한다. 동일 호스트에
        /// `setVirtualHostMapping`과 상호 배타적이다.
        public func setResourceHandler(
            resolver: KSAssetResolver, csp: String, host: String,
            crossOriginIsolation: Bool = false
        ) throws(KSError) {
            guard window.hwnd != nil else {
                throw KSError(
                    code: .windowCreationFailed,
                    message: "Window has no HWND")
            }
            try ensureWebViewInitialized(devtools: pendingDevtools)
            try webview.setResourceHandler(
                resolver: resolver, csp: csp, host: host,
                crossOriginIsolation: crossOriginIsolation)
        }

        /// WebView2의 기본 브라우저 스타일 컨텍스트 메뉴를 토글한다.
        /// `false`를 전달하면 억제된다 (페이지에서 자체 메뉴를 렌더링할 수 있음).
        public func setDefaultContextMenusEnabled(_ enabled: Bool) {
            webview.setDefaultContextMenusEnabled(enabled)
        }

        // MARK: - 네이티브 라이프사이클 훅

        /// 네이티브 `WM_CLOSE` 콜백을 설정한다. 클로저는 UI 스레드에서 실행되며
        /// `true`를 반환하면 닫기를 취소한다. `nil`을 전달하면 제거된다.
        public func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?) {
            window.onBeforeCloseSwift = cb
        }

        /// 네이티브 `WM_POWERBROADCAST(PBT_APMSUSPEND)` 콜백을 설정한다.
        /// JS 측에서는 별도 설정 없이 `__ks.system.suspend` 이벤트가
        /// 자동으로 emit되므로 프론트엔드에서 수신하는 것이 일반적이다.
        public func setOnSuspend(_ cb: (@MainActor () -> Void)?) {
            window.onSuspendSwift = cb
        }

        /// 네이티브 `WM_POWERBROADCAST(PBT_APMRESUMEAUTOMATIC|RESUMESUSPEND)`
        /// 콜백을 설정한다. JS 측에서는 `__ks.system.resume` 이벤트가
        /// 자동으로 emit된다.
        public func setOnResume(_ cb: (@MainActor () -> Void)?) {
            window.onResumeSwift = cb
        }

        /// 모든 `WM_MOVE` / `WM_SIZE(restored|maximized)` / `WM_CLOSE`에서
        /// 현재 영속 상태를 수신하는 싱크를 설치한다.
        /// `nil`을 전달하면 제거된다. `KSWindowConfig.persistState`가 설정될 때
        /// `KSWindowStateStore`를 구동하기 위해 `KSApp.boot`에서 사용한다.
        public func setWindowStateSaveSink(
            _ sink: (@MainActor (KSPersistedWindowState) -> Void)?
        ) {
            window.stateSaveSink = sink
        }

        /// 웹뷰가 외부 파일 드롱을 직접 수락할지 토글한다.
        /// `false`이면 OS 파일 드롱이 호스트 윈도우의 드롱 타겟으로
        /// 전달된다.
        public func setAllowExternalDrop(_ allow: Bool) {
            webview.setAllowExternalDrop(allow)
        }

        /// 윈도우의 HWND에 호스트 측 `IDropTarget`을 설치하여 드뜩을
        /// 브리지를 통해 `__ks.file.drop` JS 이벤트로 발행한다.
        /// `setAllowExternalDrop(false)`로 웹뷰의 내부 드롱을 비활성화한 후에만
        /// 호출해야 한다.
        ///
        /// 페이로드 스키마 (안정적 유지; `__KS_.listen`에서 소비):
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
                case .drop: kindStr = "drop"
                }
                let payload = Payload(kind: kindStr, x: x, y: y, paths: paths)
                try? bridge.emit(event: "__ks.file.drop", payload: payload)
                // 아키텍처에서는 경로가 하나라도 있을 때만 enter/drop을 수락해
                // OS가 금지 아이콘 대신 복사 커서를 표시하도록 한다.
                return !paths.isEmpty || kind == .leave
            }
        }

        /// 팝업 차단, 권한 거부-기본값, 다운로드 알림 핸들러를 설치한다.
        /// `startPrepared` / `prepare` 이후에 호출해야 한다.
        ///
        /// 다운로드 시작 이벤트는 자동으로 `__ks.webview.downloadStarting`
        /// JS 이벤트로 라우팅된다. 페이로드 스키마:
        /// ```json
        /// { "url": "<download URL>", "mimeType": "<MIME>" }
        /// ```
        ///
        /// - Parameters:
        ///   - allowPopups: `true`이면 `window.open()` 요청을 허용한다.
        ///   - openExternal: 팝업이 차단될 때 URL을 기본 브라우저에서 열 클로저.
        public func installSecurityHandlers(
            allowPopups: Bool,
            openExternal: (@MainActor (String) -> Void)?
        ) throws(KSError) {
            let bridge = self.bridge
            try webview.installSecurityHandlers(
                allowPopups: allowPopups,
                openExternal: openExternal,
                downloadEmit: { url, mime in
                    struct Payload: Encodable {
                        let url: String
                        let mimeType: String
                    }
                    try? bridge.emit(
                        event: "__ks.webview.downloadStarting",
                        payload: Payload(url: url, mimeType: mime))
                })
        }

        private var webviewInitialized = false
        private var pendingDevtools = false

        /// 2단계 시작: 웹뷰 + 가상 호스트를 준비한 후 탐색한다.
        /// 사전에 준비 단계가 없는 경우 `start(url:devtools:)`와 동일하다.
        public func startPrepared(url: String, devtools: Bool) throws(KSError) {
            pendingDevtools = devtools
            try ensureWebViewInitialized(devtools: devtools)
            try webview.navigate(url: url)
            if devtools { try? webview.openDevTools() }
        }

        /// 웹뷰가 올바른 devtools 플래그로 생성되도록 보장하여
        /// `startPrepared` 이전의 `setVirtualHostMapping` /
        /// `addDocumentCreatedScript` 호출이 잘못된 설정을 고착시키지 않도록 한다.
        public func prepare(devtools: Bool) throws(KSError) {
            pendingDevtools = devtools
            try ensureWebViewInitialized(devtools: devtools)
        }

        /// 중앙집중식 지연 웹뷰 초기화. `KSWebViewOptions`에서 윈도우별 `userDataPath`
        /// 재정의를 가져온 후 콘트롤러가 사용 가능해지면 즉시 나머지
        /// 시각 설정 (`transparent`, `disablePinchZoom`, `zoomFactor`,
        /// `backdropType`)을 적용한다. 멱등성 보장.
        private func ensureWebViewInitialized(devtools: Bool) throws(KSError) {
            if webviewInitialized { return }
            guard let hwnd = window.hwnd else {
                throw KSError(
                    code: .windowCreationFailed,
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

        /// `KSWebViewOptions` (투명도 / 핀치줌 / 줌 배율)와 선택적 Win11
        /// 시스템 배경을 적용한다. 모두 최선 노력(best-effort) 방식이다.
        private func applyVisualOptions() {
            if let backdrop = backdropType {
                window.setSystemBackdrop(backdrop)
            }
            // 윈도우 레벨 투명 또는 웹뷰 레벨 투명 중 하나라도 켜져 있으면
            // 콘트롤러 기본 배경을 알파 0으로 설정한다. WS_EX_LAYERED 윈도우가
            // 아닌 경우에도 WebView2 자체가 그리는 부분에는 적용되므로
            // 멱등적으로 안전하다. 단, 투명이 실제로 보여지려면 웹 콘텐츠
            // 자체가 불투명 배경을 그리지 않아야 한다 (`html, body { background:
            // transparent }`).
            guard let opts = webviewOptions else {
                if windowTransparent {
                    webview.setDefaultBackgroundColor(KSColorRGBA(r: 0, g: 0, b: 0, a: 0))
                }
                return
            }
            if opts.transparent || windowTransparent {
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

        /// 현재 문서를 다시 로드한다 (`location.reload()` 동등). dev 라이브
        /// 리로드(`KALSAE_DEV_RELOAD=1`)에서 사용된다. 웹뷰가 아직 초기화되지
        /// 않았다면 무시된다.
        public func reload() {
            webview.reload()
        }

        /// 클로저를 UI 스레드의 메시지 큐에 전달한다. 백그라운드 스레드 /
        /// Task.detached에서 윈도우, 웹뷰, IPC 브리지와 안전하게
        /// 상호작용할 때 사용한다. Swift의 `MainActor` 실행기가 Win32
        /// 메시지 펀프와 통합되지 않아 이 방법이 필요하다.
        nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
            window.postJob(block)
        }

        /// 데모 윈도우의 불투명 핸들. PAL 백엔드(`dialogs`, `menus`)에
        /// 모달 부모로 전달하는 데 적합하다.
        public var mainHandle: KSWindowHandle? {
            guard let hwnd = window.hwnd else { return nil }
            let raw = UInt64(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd))))
            return KSWindowHandle(label: window.label, rawValue: raw)
        }

        /// 표준 닫기 경로(`WM_DESTROY` → `PostQuitMessage`)가 실행되도록
        /// 데모 윈도우에 `WM_CLOSE`를 전달한다. `PostMessageW`를 사용하므로
        /// 모든 스레드에서 안전하게 호출할 수 있다.
        nonisolated public func requestQuit() {
            guard let hwnd = window.hwnd else { return }
            _ = PostMessageW(hwnd, UINT(WM_CLOSE), 0, 0)
        }

        /// 내장 `__ks.window.*`, `__ks.shell.*`,
        /// `__ks.clipboard.*`, `__ks.app.*` 명령을 등록하여
        /// JS 측 `__KS_.window.*` 네임스페이스가 바로 동작하도록 한다.
        ///
        /// 호스트 생성 후 (`start`/`startPrepared` 이전에) 한 번 호출하여
        /// 페이지가 첫 번째 invoke를 실행할 시점에 등록이 완료되도록 한다.
        public func registerBuiltinCommands(
            platformName: String = "Windows",
            shellScope: KSShellScope = .init(),
            notificationScope: KSNotificationScope = .init(),
            fsScope: KSFSScope = .init(),
            httpScope: KSHTTPScope = .init(),
            autostart: (any KSAutostartBackend)? = nil,
            deepLink: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = nil,
            appDirectory: URL? = nil
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
                notificationScope: notificationScope,
                fsScope: fsScope,
                httpScope: httpScope,
                autostart: autostart,
                deepLink: deepLink,
                appDirectory: appDirectory)

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

        // MARK: - 자동 승격 1회 경고

        nonisolated(unsafe) private static var didWarnBackdropAutoTransparent = false
        private static let backdropWarnLock = NSLock()

        fileprivate static func warnBackdropAutoTransparentOnce(backdrop: KSWindowBackdrop) {
            backdropWarnLock.lock()
            defer { backdropWarnLock.unlock() }
            guard !didWarnBackdropAutoTransparent else { return }
            didWarnBackdropAutoTransparent = true
            KSLog.logger("platform.windows.demohost").warning(
                "backdropType=\(backdrop.rawValue) 효과를 보이게 하려면 윈도우가 투명해야 합니다. transparent=true 로 자동 승격합니다. 이 경고를 끄려면 KSWindowConfig.transparent 를 명시적으로 true 로 지정하세요."
            )
        }
    }
#endif
