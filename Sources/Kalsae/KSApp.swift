public import Foundation
public import KalsaeCore

#if os(macOS)
internal import KalsaePlatformMac
#elseif os(Windows)
internal import KalsaePlatformWindows
#elseif os(Linux)
internal import KalsaePlatformLinux
#endif

/// High-level entry point for Kalsae applications.
///
/// `KSApp` loads `Kalsae.json`, applies its security posture, creates
/// the platform-appropriate demo host, and exposes a small cross-platform
/// API (`emit`, `postJob`, `run`) that mirrors each platform's DemoHost.
///
/// Typical usage:
/// ```swift
/// let app = try await KSApp.boot(configURL: configURL) { registry in
///     await registry.register("greet") { ... }
/// }
/// exit(app.run())
/// ```
@MainActor
public final class KSApp {
    /// Loaded application configuration (security posture, windows,
    /// menus, tray, build directories). Populated by `boot(...)` and
    /// immutable thereafter.
    public let config: KSConfig

    /// Command registry that maps `invoke(name, args)` from JS to native
    /// handlers. Apps register handlers in the `configure` closure of
    /// `boot(...)`; the registry is cooperative-actor isolated, so
    /// registration from any thread requires `await`.
    public let registry: KSCommandRegistry

    /// Platform abstraction (PAL) — exposes `dialogs`, `menus`, `tray`,
    /// `notifications`, etc. so apps can drive the host OS without
    /// importing the platform-specific module directly. `KSPlatform`
    /// itself is `Sendable`, so this property is `nonisolated` to allow
    /// access from background dispatch handlers.
    nonisolated public let platform: any KSPlatform

    #if os(Windows)
    private let host: KSWindowsDemoHost
    #elseif os(macOS)
    private let host: KSMacDemoHost
    #elseif os(Linux)
    private let host: KSLinuxDemoHost
    #endif

    private init(config: KSConfig,
                 registry: KSCommandRegistry,
                 platform: any KSPlatform,
                 host: AnyPlatformHost) {
        self.config = config
        self.registry = registry
        self.platform = platform
        // 컴파일 타임에 한 case만 활성화되므로 망라적 switch가
        // 강제 언래핑 없이 정확히 하나의 호스트를 추출한다.
        switch host {
        #if os(Windows)
        case .windows(let h): self.host = h
        #elseif os(macOS)
        case .mac(let h): self.host = h
        #elseif os(Linux)
        case .linux(let h): self.host = h
        #endif
        }
    }

    // MARK: - Single instance
    //
    // See `KSApp+SingleInstance.swift`.

    /// Boots an application from `Kalsae.json`.
    ///
    /// - Parameters:
    ///   - configURL: Absolute file URL to `Kalsae.json`.
    ///   - windowLabel: Which window from `config.windows` to open. When
    ///     `nil`, the first entry is used.
    ///   - urlOverride: When non-nil, takes precedence over
    ///     `config.windows[i].url` and the default resolution.
    ///   - resourceRoot: Overrides where static assets are served from.
    ///     When `nil`, resolved as `configURL.deletingLastPathComponent()
    ///     / config.build.frontendDist`. When the resolved directory
    ///     exists the app is served from a real HTTPS virtual host
    ///     (`https://app.Kalsae/`) instead of `file://`, enabling
    ///     header-level security such as a proper CSP.
    ///   - configure: Invoked before the message loop starts. Register
    ///     commands here.
    public static func boot(
        configURL: URL,
        windowLabel: String? = nil,
        urlOverride: String? = nil,
        resourceRoot: URL? = nil,
        configure: (KSCommandRegistry) async throws(KSError) -> Void
    ) async throws(KSError) -> KSApp {
        let config = try KSConfigLoader.load(from: configURL)
        let root = resourceRoot ?? {
            let dir = configURL.deletingLastPathComponent()
            return dir.appendingPathComponent(config.build.frontendDist)
        }()
        return try await boot(
            config: config,
            windowLabel: windowLabel,
            urlOverride: urlOverride,
            resourceRoot: root,
            configure: configure)
    }

    /// Boots an application from an in-memory `KSConfig`. Useful for
    /// tests and for apps that assemble their config programmatically.
    public static func boot(
        config: KSConfig,
        windowLabel: String? = nil,
        urlOverride: String? = nil,
        resourceRoot: URL? = nil,
        configure: (KSCommandRegistry) async throws(KSError) -> Void
    ) async throws(KSError) -> KSApp {
        // 1. 윈도우 선택.
        let window = try selectWindow(from: config, label: windowLabel)

        // 2. 사용자 명령 등록 이전에 명령 제한목록을 적용한다.
        //    이렇게 해야 `setAllowlist(nil)` (Codable 기본값)이
        //    "등록된 모든 명령 허용"의 의미를 유지한다.
        let registry = KSCommandRegistry()
        await registry.setAllowlist(config.security.commandAllowlist)

        // 3. 사용자 등록 블록 실행. 시그니처가 `throws(KSError)`이므로 추가
        //    `as?` 분기 없이 그대로 전파한다.
        try await configure(registry)

        // 4. 플랫폼 호스트 구성.
        #if os(Windows)
        let concrete = try KSWindowsDemoHost(
            windowConfig: window, registry: registry)
        let wrapper = AnyPlatformHost.windows(concrete)
        #elseif os(macOS)
        let concrete = try KSMacDemoHost(
            windowConfig: window, registry: registry)
        let wrapper = AnyPlatformHost.mac(concrete)
        #elseif os(Linux)
        let concrete = try KSLinuxDemoHost(
            windowConfig: window, registry: registry)
        let wrapper = AnyPlatformHost.linux(concrete)
        #else
        throw KSError.unsupportedPlatform(
            "KSApp requires macOS, Windows, or Linux")
        #endif

        // 5. 프론트엔드 제공 방식 결정.
        let servingMode = decideServingMode(
            urlOverride: urlOverride,
            windowURL: window.url,
            devServerURL: config.build.devServerURL,
            resourceRoot: resourceRoot)

        if case .virtualHost(let servedRoot) = servingMode {
            #if os(Windows)
            try concrete.prepare(devtools: config.security.devtools)
            // WebResourceRequested를 통한 헤더 기반 CSP. 가상 호스트 매핑은
            // 사용하지 않는다 — 이는 헤더 수정이 불가능한 엔진 내부 응답을
            // 반환하기 때문이다. 대신 `https://{virtualHost}/*` 아래 모든
            // 요청을 가로채 `KSAssetResolver`가 제공하고, 각 응답에
            // Content-Security-Policy를 붙여준다.
            //
            // Phase 9: 동일 자산이 webview lifecycle 동안 여러 번 요청되는
            // 정상 패턴 — 디스크 재읽기를 피하기 위해 작은 LRU 캐시를 단다.
            let resolver = KSAssetResolver(
                root: servedRoot, cache: KSAssetCache())
            try concrete.setResourceHandler(
                resolver: resolver,
                csp: config.security.csp,
                host: Self.virtualHost)
            #elseif os(macOS) || os(Linux)
            try concrete.setAssetRoot(servedRoot)
            #endif
            #if os(Linux)
            try concrete.setResponseCSP(config.security.csp)
            #endif
        }

        // CSP 주입 (document-created 스크립트). 헤더 CSP가 활성화되더라도
        // meta 태그는 WebView2/WKWebView/WebKitGTK 모두에서 통하는 공통 동작
        // 기반이므로 모든 부팅에서 항상 포함한다.
        let cspScript = Self.cspInjectionScript(config.security.csp)
        try concrete.addDocumentCreatedScript(cspScript)

        // 보안 설정의 context-menu / external-drop 정책 적용.
        #if os(Windows)
        if config.security.contextMenu == .disabled {
            concrete.setDefaultContextMenusEnabled(false)
        }
        if !config.security.allowExternalDrop {
            concrete.setAllowExternalDrop(false)
            // Phase 5-3: webview 기본 드롭을 호스트의 IDropTarget으로 교체해
            // OS 파일 드롭이 JS에서 `__ks.file.drop` 이벤트로 올라오도록 한다.
            // 시도·실패 동작: OLE 등록이 실패해도(예: STA에 진입 불가능한
            // 스레드) 로그만 남기고 부팅을 계속한다.
            do {
                try concrete.installFileDropEmitter()
            } catch {
                KSLog.logger("kalsae.app").warning(
                    "installFileDropEmitter failed: \(error)")
            }
        }
        #endif

        // 6. URL 결정 — 오버라이드와 윈도우 자체 `url` 세팅을 존중한다.
        let url = resolveStartURL(
            urlOverride: urlOverride,
            windowURL: window.url,
            devServerURL: config.build.devServerURL,
            servingMode: servingMode)

        #if os(Windows)
        try concrete.startPrepared(url: url, devtools: config.security.devtools)
        #else
        try concrete.start(url: url, devtools: config.security.devtools)
        #endif

        let platform = try Kalsae.makePlatform()

        // 알림 백엔드를 트레이 아이콘과 연결해 토스트가 상주 아이콘을
        // 경유해 울리도록 한다. 윈도우즈 외 플랫폼에서는 노옵.
        #if os(Windows)
        bindNotificationsToTray(platform: platform)
        #endif

        // 내장 `__ks.window/shell/clipboard/app/environment` 명령을 등록해
        // JS 쪽 `__KS_.window.*`, `__KS_.shell.*`, `__KS_.clipboard.*`,
        // `__KS_.app.*` 네임스페이스가 즉시 동작하도록 한다. 해당
        // 백엔드가 노출된 플랫폼에서만 사용 가능하다.
        #if os(Windows)
        await concrete.registerBuiltinCommands(
            platformName: platform.name,
            shellScope: config.security.shell,
            notificationScope: config.security.notifications)
        #endif

        let app = KSApp(config: config, registry: registry,
                        platform: platform, host: wrapper)

        // 7. 네이티브 메뉴 / 트레이 클릭을 구독한다.
        #if os(Windows)
        subscribeMenuRouter(app: app)
        #endif

        return app
    }

    // virtualHost / cspInjectionScript / isDirectory / isRemoteURL —
    // see `KSApp+Helpers.swift`.

    /// Posts a closure onto the UI thread. Thread-safe.
    nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
        host.postJob(block)
    }

    /// Emits a `__KB_.listen`-compatible event to the frontend.
    public func emit(_ event: String, payload: any Encodable) throws(KSError) {
        try host.emit(event, payload: payload)
    }

    /// Runs the platform message loop until exit.
    public func run() -> Int32 {
        host.runMessageLoop()
    }

    /// Requests an orderly shutdown of the application. On Windows this
    /// posts `WM_CLOSE` to the demo window; on macOS this terminates
    /// `NSApplication`; on Linux this requests `GtkApplication` quit.
    nonisolated public func quit() {
        #if os(Windows)
        host.requestQuit()
        #elseif os(macOS)
        host.requestQuit()
        #elseif os(Linux)
        host.requestQuit()
        #endif
    }

    // MARK: - Phase C4 native lifecycle callbacks
    //
    // These hand the closure straight to the platform host. On Windows
    // they fire from `WndProc` (UI thread); on macOS / Linux preview
    // they're accepted but currently no-op until each PAL implements
    // the corresponding system events.

    /// Native close intercept. The closure runs on the UI thread when
    /// the user attempts to close the window (e.g. clicks the [X] or
    /// presses Alt-F4). Return `true` to cancel the close; return
    /// `false` to let the platform's default behaviour run (which may
    /// itself be `hideOnClose` / `__ks.window.beforeClose`). Pass `nil`
    /// to remove the callback.
    public func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?) {
        host.setOnBeforeClose(cb)
    }

    /// Invoked when the OS signals power suspend (Windows
    /// `PBT_APMSUSPEND`). Best-effort — the system may suspend the
    /// process before the callback dispatches.
    public func setOnSuspend(_ cb: (@MainActor () -> Void)?) {
        host.setOnSuspend(cb)
    }

    /// Invoked when the OS signals power resume (Windows
    /// `PBT_APMRESUMEAUTOMATIC` / `PBT_APMRESUMESUSPEND`).
    public func setOnResume(_ cb: (@MainActor () -> Void)?) {
        host.setOnResume(cb)
    }

    // MARK: - UI-thread convenience helpers — see `KSApp+UI.swift`.
}
