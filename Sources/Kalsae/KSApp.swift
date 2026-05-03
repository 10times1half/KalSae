public import Foundation
public import KalsaeCore

/// Kalsae 애플리케이션의 최상위 진입점.
///
/// `KSApp`은 `Kalsae.json`을 로드하고, 보안 설정을 적용하며,
/// 플랫폼에 맞는 데모 호스트를 생성하고, 각 플랫폼의 DemoHost가
/// 제공하는 소형 크로스플랫폼 API(`emit`, `postJob`, `run`)를 노출한다.
///
/// 일반적인 사용법:
/// ```swift
/// let app = try await KSApp.boot(configURL: configURL) { registry in
///     await registry.register("greet") { ... }
/// }
/// exit(app.run())
/// ```
#if os(macOS)
    internal import KalsaePlatformMac
#elseif os(Windows)
    internal import KalsaePlatformWindows
#elseif os(Linux)
    internal import KalsaePlatformLinux
#elseif os(iOS)
    internal import KalsaePlatformIOS
#elseif os(Android)
    internal import KalsaePlatformAndroid
#endif
@MainActor
public final class KSApp {
    /// 로드된 애플리케이션 설정 (보안 설정, 윈도우, 메뉴, 트레이, 빌드 디렉터리).
    /// `boot(...)`에서 채워지며 이후 불변이다.
    public let config: KSConfig

    /// JS의 `invoke(name, args)`를 네이티브 핸들러에 매핑하는 명령 레지스트리.
    /// 앱은 `boot(...)`의 `configure` 클로저에서 핸들러를 등록한다;
    /// 레지스트리는 협력 액터로 격리되어 있으므로 모든 스레드에서의
    /// 등록에는 `await`가 필요하다.
    public let registry: KSCommandRegistry

    /// 플랫폼 추상화 계층(PAL) — `dialogs`, `menus`, `tray`,
    /// `notifications` 등을 노출해 앱이 플랫폼별 모듈을 직접 임포트하지
    /// 않고도 호스트 OS를 구동할 수 있게 한다. `KSPlatform` 자체는
    /// `Sendable`이므로 이 프로퍼티는 `nonisolated`로 선언되어
    /// 백그라운드 디스패치 핸들러에서 접근할 수 있다.
    nonisolated public let platform: any KSPlatform

    #if os(Windows)
        private let host: KSWindowsDemoHost
    #elseif os(macOS)
        private let host: KSMacDemoHost
    #elseif os(Linux)
        private let host: KSLinuxDemoHost
    #elseif os(iOS)
        private let host: KSiOSDemoHost
    #elseif os(Android)
        private let host: KSAndroidDemoHost
    #endif

    /// `config.deepLink`가 선언되었을 때 설치되는 선택적 딥링크 백엔드.
    /// `dispatchDeepLinkURLs`에서 들어오는 인자를 필터링하고
    /// `__ks.deepLink.openURL` 이벤트를 방출하는 데 사용된다.
    private let deepLinkBackend: (any KSDeepLinkBackend)?

    /// 두 번째 이후 윈도우 호스트 컬렉션. primary `host`와 함께 앱 수명 동안 살아있어
    /// 각 플랫폼 호스트의 Win32Window/NSWindow와 WebView2Bridge가 유지된다.
    ///
    /// 의도적으로 "저장만" 한다 — 다른 코드에서 읽지 않으나, 이 배열을
    /// 잡고 있지 않으면 보조 창의 `Win32Window`/`KSMacWindow`와
    /// 동반된 IPC 브리지가 deinit되어 창이 즉시 사라진다. 삭제 금지.
    private let secondaryHosts: [AnyPlatformHost]

    private init(
        config: KSConfig,
        registry: KSCommandRegistry,
        platform: any KSPlatform,
        host: AnyPlatformHost,
        secondaryHosts: [AnyPlatformHost] = [],
        deepLinkBackend: (Any)? = nil
    ) {
        self.config = config
        self.registry = registry
        self.platform = platform
        self.deepLinkBackend = deepLinkBackend as? any KSDeepLinkBackend
        self.secondaryHosts = secondaryHosts
        // 컴파일 타임에 한 case만 활성화되므로 망라적 switch가
        // 강제 언래핑 없이 정확히 하나의 호스트를 추출한다.
        switch host {
        #if os(Windows)
            case .windows(let h): self.host = h
        #elseif os(macOS)
            case .mac(let h): self.host = h
        #elseif os(Linux)
            case .linux(let h): self.host = h
        #elseif os(iOS)
            case .ios(let h): self.host = h
        #elseif os(Android)
            case .android(let h): self.host = h
        #endif
        }
    }

    // MARK: - 단일 인스턴스
    //
    // `KSApp+SingleInstance.swift` 참조.

    /// `Kalsae.json`에서 애플리케이션을 부팅한다.
    ///
    /// - Parameters:
    ///   - configURL: `Kalsae.json`의 절대 파일 URL.
    ///   - windowLabel: `config.windows`에서 열 윈도우. `nil`이면 첫 번째 항목이 사용된다.
    ///   - urlOverride: nil이 아닐 경우 `config.windows[i].url` 및 기본 해상도보다 우선한다.
    ///   - resourceRoot: 정적 자산이 제공되는 위치를 재정의한다.
    ///     `nil`일 경우 `configURL.deletingLastPathComponent() / config.build.frontendDist`로
    ///     결정된다. 해결된 디렉터리가 존재하면 앱은 `file://` 대신 실제 HTTPS 가상 호스트
    ///     (`https://app.Kalsae/`)에서 제공되어 적절한 CSP와 같은 헤더 수준 보안이 가능해진다.
    ///   - configure: 메시지 루프가 시작되기 전에 호출된다. 여기서 명령을 등록한다.
    public static func boot(
        configURL: URL,
        windowLabel: String? = nil,
        urlOverride: String? = nil,
        resourceRoot: URL? = nil,
        configure: (KSCommandRegistry) async throws(KSError) -> Void
    ) async throws(KSError) -> KSApp {
        let config = try KSConfigLoader.load(from: configURL)
        let root =
            resourceRoot
            ?? {
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

    /// 메모리 내 `KSConfig`에서 애플리케이션을 부팅한다. 테스트와
    /// 설정을 프로그래밍 방식으로 조합하는 앱에 유용하다.
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
            // Phase 8: 윈도우 상태 영속화 — `persistState=true`일 때만 활성화.
            // 부팅 직후의 첫 `Win32Window.init`에서 복원 상태를 적용해야 하므로
            // 호스트 생성 전에 store를 만들고 load한다.
            let stateStore: KSWindowStateStore? =
                window.persistState
                ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
                : nil
            let restoredState = stateStore?.load(label: window.label)

            let concrete = try KSWindowsDemoHost(
                windowConfig: window, registry: registry,
                restoredState: restoredState)
            let wrapper = AnyPlatformHost.windows(concrete)

            // 저장 sink 설치 — WM_MOVE/SIZE/CLOSE에서 호출되며 디스크 쓰기는
            // `KSWindowStateStore.save`가 atomic + 비-atomic 폴백으로 처리한다.
            if let store = stateStore {
                let label = window.label
                concrete.setWindowStateSaveSink { state in
                    _ = store.save(label: label, state: state)
                }
            }
        #elseif os(macOS)
            let stateStore: KSWindowStateStore? =
                window.persistState
                ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
                : nil
            let concrete = try KSMacDemoHost(
                windowConfig: window, registry: registry)
            let wrapper = AnyPlatformHost.mac(concrete)

            if let store = stateStore {
                let label = window.label
                concrete.setWindowStateSaveSink { state in
                    _ = store.save(label: label, state: state)
                }
            }
        #elseif os(Linux)
            let concrete = try KSLinuxDemoHost(
                windowConfig: window, registry: registry)
            let wrapper = AnyPlatformHost.linux(concrete)
        #elseif os(iOS)
            let concrete = try KSiOSDemoHost(
                windowConfig: window, registry: registry)
            let wrapper = AnyPlatformHost.ios(concrete)
        #elseif os(Android)
            let concrete = try KSAndroidDemoHost(
                windowConfig: window, registry: registry)
            let wrapper = AnyPlatformHost.android(concrete)
        #else
            throw KSError.unsupportedPlatform(
                "KSApp requires macOS, Windows, Linux, iOS, or Android")
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
            #elseif os(macOS) || os(Linux) || os(iOS) || os(Android)
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

        // 7. 두 번째 이후 윈도우 부팅 — Windows/macOS 전용 (v0.3).
        // Linux/iOS/Android 는 single-window 유지.
        var secondaryWrappers: [AnyPlatformHost] = []
        #if os(Windows)
            for secondaryConfig in config.windows where secondaryConfig.label != window.label {
                let secStateStore: KSWindowStateStore? =
                    secondaryConfig.persistState
                    ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
                    : nil
                let secRestoredState = secStateStore?.load(label: secondaryConfig.label)
                let sec = try KSWindowsDemoHost(
                    windowConfig: secondaryConfig, registry: registry,
                    restoredState: secRestoredState)
                let secMode = decideServingMode(
                    urlOverride: nil, windowURL: secondaryConfig.url,
                    devServerURL: config.build.devServerURL, resourceRoot: resourceRoot)
                if case .virtualHost(let secRoot) = secMode {
                    try sec.prepare(devtools: config.security.devtools)
                    let secAssetResolver = KSAssetResolver(root: secRoot, cache: KSAssetCache())
                    try sec.setResourceHandler(
                        resolver: secAssetResolver,
                        csp: config.security.csp,
                        host: Self.virtualHost)
                }
                try sec.addDocumentCreatedScript(cspScript)
                if config.security.contextMenu == .disabled {
                    sec.setDefaultContextMenusEnabled(false)
                }
                if !config.security.allowExternalDrop {
                    sec.setAllowExternalDrop(false)
                    do {
                        try sec.installFileDropEmitter()
                    } catch {
                        KSLog.logger("kalsae.app").warning(
                            "secondary '\(secondaryConfig.label)' installFileDropEmitter failed: \(error)")
                    }
                }
                if let store = secStateStore {
                    let lbl = secondaryConfig.label
                    sec.setWindowStateSaveSink { state in _ = store.save(label: lbl, state: state) }
                }
                let secURL = resolveStartURL(
                    urlOverride: nil, windowURL: secondaryConfig.url,
                    devServerURL: config.build.devServerURL, servingMode: secMode)
                try sec.startPrepared(url: secURL, devtools: config.security.devtools)
                secondaryWrappers.append(.windows(sec))
            }
        #elseif os(macOS)
            for secondaryConfig in config.windows where secondaryConfig.label != window.label {
                let secStateStore: KSWindowStateStore? =
                    secondaryConfig.persistState
                    ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
                    : nil
                let sec = try KSMacDemoHost(windowConfig: secondaryConfig, registry: registry)
                let secMode = decideServingMode(
                    urlOverride: nil, windowURL: secondaryConfig.url,
                    devServerURL: config.build.devServerURL, resourceRoot: resourceRoot)
                if case .virtualHost(let secRoot) = secMode {
                    try sec.setAssetRoot(secRoot)
                }
                try sec.addDocumentCreatedScript(cspScript)
                if let store = secStateStore {
                    let lbl = secondaryConfig.label
                    sec.setWindowStateSaveSink { state in _ = store.save(label: lbl, state: state) }
                }
                let secURL = resolveStartURL(
                    urlOverride: nil, windowURL: secondaryConfig.url,
                    devServerURL: config.build.devServerURL, servingMode: secMode)
                try sec.start(url: secURL, devtools: config.security.devtools)
                secondaryWrappers.append(.mac(sec))
            }
        #elseif os(Linux) || os(iOS) || os(Android)
            // 단일 창만 지원하는 플랫폼: `config.windows`에 두 개 이상 선언되어 있으면
            // 정적으로 버려진다. 사용자가 "왜 두 번째 창이 안 뜨지?" 디버깅하지
            // 않도록 부팅 시 1회 경고를 남긴다.
            if config.windows.count > 1 {
                let ignored = config.windows.count - 1
                KSLog.logger("kalsae.app").warning(
                    "Multiple windows declared (\(config.windows.count)) but this platform "
                        + "supports single-window only; ignoring \(ignored) entries.")
            }
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

        // 모든 플랫폼: autostart 백엔드. config에 `autostart` 섹션이 있을 때만 활성화.
        let autostartBackend: (any KSAutostartBackend)? = {
            #if os(Windows)
                guard let autostartCfg = config.autostart else { return nil }
                return KSWindowsAutostartBackend(
                    identifier: config.app.identifier,
                    args: autostartCfg.args)
            #elseif os(macOS)
                guard config.autostart != nil else { return nil }
                return KSMacAutostartBackend()
            #elseif os(Linux)
                guard config.autostart != nil else { return nil }
                return KSLinuxAutostartBackend(identifier: config.app.identifier)
            #elseif os(iOS)
                guard config.autostart != nil else { return nil }
                return KSiOSAutostartBackend()
            #elseif os(Android)
                guard config.autostart != nil else { return nil }
                return KSAndroidAutostartBackend()
            #else
                return nil
            #endif
        }()

        // 모든 플랫폼: deepLink 백엔드. config에 `deepLink` 섹션이 있을 때만 활성화.
        let builtDeepLinkBackend: (any KSDeepLinkBackend)? = {
            guard let dlc = config.deepLink else { return nil }
            let b: any KSDeepLinkBackend
            #if os(Windows)
                b = KSWindowsDeepLinkBackend(identifier: config.app.identifier)
            #elseif os(macOS)
                KSMacDeepLinkBackend.installAppleEventHandler()
                b = KSMacDeepLinkBackend(identifier: config.app.identifier)
            #elseif os(Linux)
                b = KSLinuxDeepLinkBackend(identifier: config.app.identifier)
            #elseif os(iOS)
                b = KSiOSDeepLinkBackend(identifier: config.app.identifier)
            #elseif os(Android)
                b = KSAndroidDeepLinkBackend(identifier: config.app.identifier)
                KSAndroidDeepLinkBackend.knownSchemes = Set(dlc.schemes.map { $0.lowercased() })
            #else
                return nil
            #endif
            if dlc.autoRegisterOnLaunch {
                for s in dlc.schemes {
                    do {
                        try b.register(scheme: s)
                    } catch {
                        KSLog.logger("kalsae.app").error(
                            "deepLink auto-register failed for '\(s)': \(error)")
                    }
                }
            }
            return b
        }()

        let deepLinkPair: (backend: any KSDeepLinkBackend, config: KSDeepLinkConfig)? = {
            guard let b = builtDeepLinkBackend, let dlc = config.deepLink else { return nil }
            return (b, dlc)
        }()

        // 모든 플랫폼: JS `__ks.*` 내장 명령 등록.
        await concrete.registerBuiltinCommands(
            platformName: platform.name,
            shellScope: config.security.shell,
            notificationScope: config.security.notifications,
            fsScope: config.security.fs,
            httpScope: config.security.http,
            autostart: autostartBackend,
            deepLink: deepLinkPair,
            appDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

        let app = KSApp(
            config: config, registry: registry,
            platform: platform, host: wrapper,
            secondaryHosts: secondaryWrappers,
            deepLinkBackend: builtDeepLinkBackend)

        // 7. 네이티브 메뉴 / 트레이 클릭을 구독한다.
        #if os(Windows) || os(Linux)
            subscribeMenuRouter(app: app)
        #endif

        return app
    }

    // virtualHost / cspInjectionScript / isDirectory / isRemoteURL —
    // `KSApp+Helpers.swift` 참조.

    /// 클로저를 UI 스레드에 게시한다. 스레드 안전.
    nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
        host.postJob(block)
    }

    /// 프론트엔드에 `__KB_.listen` 호환 이벤트를 방출한다.
    public func emit(_ event: String, payload: any Encodable) throws(KSError) {
        try host.emit(event, payload: payload)
    }

    /// 특정 창의 프론트엔드에 이벤트를 방출한다.
    ///
    /// `label`이 등록된 창 레이블과 일치하지 않으면 아무 동작도 하지 않는다.
    /// `label`이 `nil`이면 열려 있는 모든 창에 브로드캐스트한다.
    @MainActor
    public func emit(
        _ event: String,
        payload: any Encodable,
        to label: String?
    ) throws(KSError) {
        try KSWindowEmitHub.shared.emit(event: event, payload: payload, to: label)
    }

    /// `args`에서 선언된 딥링크 URL을 필터링하고 일치하는 각 URL에 대해
    /// 하나의 `__ks.deepLink.openURL` 이벤트를 방출한다. 페이로드는
    /// `{ "url": "<scheme>://..." }`이다. 앱에 딥링크 설정이 없어도
    /// 안전하게 호출할 수 있다 — 호출은 아무 동작도 하지 않는다.
    ///
    /// 권장 호출 위치:
    ///   * `KSApp.singleInstance`의 `onSecondInstance` 콜백 내에서,
    ///     전달된 argv를 전달.
    ///   * 시작 시 `CommandLine.arguments`로 한 번 호출해 페이지가
    ///     앱이 실행된 URL을 관찰할 수 있도록.
    public func dispatchDeepLinkURLs(args: [String]) {
        guard let backend = deepLinkBackend, let dlc = config.deepLink else { return }
        var urls = backend.currentLaunchURLs(forSchemes: dlc.schemes)
        urls.append(contentsOf: backend.extractURLs(fromArgs: args, forSchemes: dlc.schemes))
        var seen: Set<String> = []
        struct Payload: Encodable { let url: String }
        for u in urls {
            if !seen.insert(u).inserted { continue }
            // 보안: 악의적인 명령줄 인자나 두 번째 인스턴스 전달로 인한
            // DoS를 방지하기 위해 긴 URL을 거부한다.
            guard u.utf8.count <= 4096 else {
                KSLog.logger("kalsae.app").warning(
                    "deepLink URL exceeds 4 KB limit (\(u.utf8.count) bytes); dropped")
                continue
            }
            do {
                try emit("__ks.deepLink.openURL", payload: Payload(url: u))
            } catch {
                KSLog.logger("kalsae.app").error(
                    "deepLink emit failed for '\(u)': \(error)")
            }
        }
    }

    /// 종료될 때까지 플랫폼 메시지 루프를 실행한다.
    public func run() -> Int32 {
        host.runMessageLoop()
    }

    /// 애플리케이션의 정리된 종료를 요청한다. Windows에서는 데모 윈도우에
    /// `WM_CLOSE`를 게시하고, macOS에서는 `NSApplication`을 종료하며,
    /// Linux에서는 `GtkApplication` 종료를 요청한다.
    nonisolated public func quit() {
        #if os(Windows)
            host.requestQuit()
        #elseif os(macOS)
            host.requestQuit()
        #elseif os(Linux)
            host.requestQuit()
        #elseif os(iOS)
            host.requestQuit()
        #elseif os(Android)
            host.requestQuit()
        #endif
    }

    // MARK: - 네이티브 라이프사이클 콜백
    //
    // 클로저를 플랫폼 호스트에 직접 전달한다. Windows에서는 `WndProc`
    // (UI 스레드)에서 실행된다; macOS/Linux 프리뷰에서는 수용되지만
    // 각 PAL이 해당 시스템 이벤트를 구현할 때까지 현재는 노옵이다.

    /// 네이티브 닫기 가로채기. 사용자가 윈도우를 닫으려고 할 때
    /// (예: [X] 클릭 또는 Alt-F4) UI 스레드에서 클로저가 실행된다.
    /// `true`를 반환하면 닫기를 취소하고, `false`를 반환하면 플랫폼의
    /// 기본 동작(`hideOnClose` / `__ks.window.beforeClose`일 수 있음)이
    /// 실행된다. `nil`을 전달하면 콜백을 제거한다.
    public func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?) {
        host.setOnBeforeClose(cb)
    }

    /// OS가 전원 일시 중단을 알릴 때 호출된다 (Windows
    /// `PBT_APMSUSPEND`). 최선 노력 — 콜백이 디스패치되기 전에
    /// 시스템이 프로세스를 일시 중단할 수 있다.
    public func setOnSuspend(_ cb: (@MainActor () -> Void)?) {
        host.setOnSuspend(cb)
    }

    /// OS가 전원 재개를 알릴 때 호출된다 (Windows
    /// `PBT_APMRESUMEAUTOMATIC` / `PBT_APMRESUMESUSPEND`).
    public func setOnResume(_ cb: (@MainActor () -> Void)?) {
        host.setOnResume(cb)
    }

    // MARK: - UI 스레드 편의 헬퍼 — `KSApp+UI.swift` 참조.
}
