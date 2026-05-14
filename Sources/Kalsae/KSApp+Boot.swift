internal import Foundation
internal import KalsaeCore

#if os(macOS)
    internal import KalsaePlatformMac
#elseif os(Windows)
    internal import KalsaePlatformWindows
#elseif os(Linux)
    internal import KalsaePlatformLinux
#elseif os(iOS)
    internal import KalsaePlatformIOS
#endif

// MARK: - 종료

extension KSApp {
    // MARK: - 부팅 단계
    //
    // `boot(config:)`에서 추출한 순수 함수 / 플랫폼별 사이드이펙트 헬퍼.
    // 각 헬퍼는 단일 부팅 단계를 캡슐화한다.

    /// 부팅할 윈도우 설정을 선택한다. `label`과 일치하는 항목을 반환하거나,
    /// `label`이 `nil`이면 설정에 선언된 첫 번째 윈도우를 반환한다.
    static func selectWindow(
        from config: KSConfig, label: String?
    ) throws(KSError) -> KSWindowConfig {
        try KSBootOrchestrator.selectWindow(from: config, label: label)
    }

    /// 프론트엔드 제공 방식 결정 결과 — `KSBootOrchestrator.ServingMode`의 별칭.
    typealias ServingMode = KSBootOrchestrator.ServingMode

    static func decideServingMode(
        urlOverride: String?,
        windowURL: String?,
        devServerURL: String,
        resourceRoot: URL?
    ) -> ServingMode {
        // dev 서버 reachability 검사. DEBUG/RELEASE 모두에서 활성화한다 —
        // RELEASE 빌드라도 `kalsae build` 가 `devServerURL` 을 비우지 않는
        // 한 (또는 사용자가 `kalsae dev` 로 RELEASE 산출물을 실행하는 한)
        // dev 서버가 떠 있지 않으면 가상 호스트로 폴백해야 흰 화면을 피한다.
        let probe: (String) -> Bool = { Self.isDevServerReachable($0) }
        // probe 실패 시 한 줄 진단 로그 — `KSBootOrchestrator` 는 stateless 라
        // 로깅 책임은 호출자(KSApp)가 진다.
        let isRemote = KSBootOrchestrator.isRemoteURL(devServerURL)
        if urlOverride == nil, windowURL == nil, isRemote {
            if !probe(devServerURL) {
                KSLog.logger("kalsae.app").warning(
                    "dev server unreachable at \(devServerURL); falling back to virtualHost/file"
                )
            }
        }
        let preferEmbedded: Bool
        #if os(Windows)
            preferEmbedded = KSEmbeddedAssetResolverFactory.shouldPreferEmbeddedAssets()
        #else
            preferEmbedded = false
        #endif
        return KSBootOrchestrator.decideServingMode(
            urlOverride: urlOverride,
            windowURL: windowURL,
            devServerURL: devServerURL,
            resourceRoot: resourceRoot,
            isDevServerReachable: probe,
            preferEmbeddedAssets: preferEmbedded)
    }

    /// 윈도우에 로드할 실제 URL 문자열을 결정한다. 우선순위:
    /// 호출별 오버라이드 → 윈도우별 URL → 가상 호스트 기본값
    /// → 라이브 dev 서버 → fallback 분기는 진단 `data:` URL 로 대체.
    ///
    /// `.fallback` 은 "가상 호스트도 없고 dev 서버도 응답하지 않는다"는 의미라
    /// `devServerURL` 로 바로 navigate 하면 결국 `chrome-error://chromewebdata/`
    /// 흰 화면이 된다. 대신 시도한 URL 과 다음 단계 안내가 든 진단 페이지를
    /// 띄워 사용자가 즉시 원인을 알 수 있게 한다.
    static func resolveStartURL(
        urlOverride: String?,
        windowURL: String?,
        devServerURL: String,
        servingMode: ServingMode
    ) -> String {
        #if os(Windows)
            let virtualURL = "https://\(virtualHost)/index.html"
        #else
            // WebKit은 커스텀 스키마가 필요하다 — http/https에는 스키마
            // 핸들러를 등록할 수 없다. 크로스플랫폼에서 `ks://app/...`을 쓴다.
            let virtualURL = "ks://app/index.html"
        #endif
        return KSBootOrchestrator.resolveStartURL(
            urlOverride: urlOverride,
            windowURL: windowURL,
            devServerURL: devServerURL,
            servingMode: servingMode,
            virtualHostURL: virtualURL,
            fallbackURL: diagnosticDataURL(attemptedURL: devServerURL))
    }

    #if os(Windows)
        /// `KSWindowsCommandRouter` 클릭을 (a) 프론트엔드로 전송되는 `"menu"` 이벤트와
        /// (b) 일치하는 `@KSCommand` 핸들러의 레지스트리 디스패치에 연결한다.
        /// `app`을 약하게 참조한다.
        static func subscribeMenuRouter(app: KSApp) {
            KSWindowsCommandRouter.shared.subscribe { [weak app] command, itemID in
                guard let app else { return }
                struct MenuClickPayload: Encodable {
                    let command: String
                    let itemID: String?
                }
                let payload = MenuClickPayload(command: command, itemID: itemID)
                do {
                    try app.emit("menu", payload: payload)
                } catch {
                    KSLog.logger("kalsae.app").error(
                        "failed to emit 'menu' event for '\(command)': \(error)")
                }
                // 레지스트리로 분배. 메뉴 구동 명령은 인자 없는
                // `@KSCommand`로 설계되어 있다.
                let registry = app.registry
                Task.detached {
                    _ = await registry.dispatch(
                        name: command,
                        args: Data("{}".utf8))
                }
            }
        }

        /// Windows 알림 백엔드를 트레이 아이콘을 통해 연결해 토스트가
        /// 상주 쉘 아이콘을 경유해 표시되도록 한다. `attachTray`가 약한 참조를
        /// 저장하므로 `tray.install(...)` 전에 호출해도 안전하다.
        static func bindNotificationsToTray(platform: any KSPlatform) {
            if let nbackend = platform.notifications as? KSWindowsNotificationBackend,
                let traybackend = platform.tray as? KSWindowsTrayBackend
            {
                nbackend.attachTray(traybackend)
            }
        }
    #elseif os(Linux)
        static func subscribeMenuRouter(app: KSApp) {
            KSLinuxCommandRouter.shared.subscribe { [weak app] command, itemID in
                guard let app else { return }
                struct MenuClickPayload: Encodable {
                    let command: String
                    let itemID: String?
                }
                let payload = MenuClickPayload(command: command, itemID: itemID)
                do {
                    try app.emit("menu", payload: payload)
                } catch {
                    KSLog.logger("kalsae.app").error(
                        "failed to emit 'menu' event for '\(command)': \(error)")
                }
                let registry = app.registry
                Task.detached {
                    _ = await registry.dispatch(
                        name: command,
                        args: Data("{}".utf8))
                }
            }
        }
    #endif
}
extension KSApp {
    /// 최선의 우아한 종료를 수행한다: 트레이 아이콘 제거, IPC 브리지 등록 해제,
    /// 라이프사이클 이벤트 로깅.
    ///
    /// OS가 종료 신호를 보내면 플랫폼 런루프가 자동으로 이 메서드를 호출한다;
    /// 앱 코드에서도 테스트나 제어된 정리 중에 명시적으로 호출할 수 있다.
    ///
    /// 작업 순서:
    /// 1. 트레이 아이콘 제거 (고립된 쉘 알림 아이콘 방지).
    /// 2. 모든 내장 명령의 레지스트리 등록 해제.
    /// 3. 라이프사이클 로그 항목.
    public func shutdown() async {
        // 1. 고립된 쉘 상태 항목을 피하기 위해 트레이 아이콘 제거.
        if let tray = platform.tray {
            await tray.remove()
        }
        // 1.5. dev 라이브 리로드 watcher 작업 취소 (실행 중일 때만).
        devWatcherTask?.cancel()
        devWatcherTask = nil
        // 2. 플러그인 teardown — 등록 역순, best-effort.
        let ctx = DefaultPluginContext(app: self)
        for plugin in _pluginsStorage.reversed() {
            await plugin.teardown(ctx)
        }
        _pluginsStorage.removeAll()
        // 3. 모든 등록된 명령을 해제해 이후 디스패치가 해제된 핸들러에
        //    도달하는 대신 commandNotFound를 반환하도록 한다.
        let names = await registry.registered()
        for name in names {
            await registry.unregister(name)
        }
        // 4. 로깅.
        KSLog.logger("kalsae.app").info("KSApp shutdown complete")
    }
}
