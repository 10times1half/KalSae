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
        if let label {
            guard let match = config.windows.first(where: { $0.label == label }) else {
                throw KSError.configInvalid("no window labelled '\(label)'")
            }
            return match
        }
        guard let first = config.windows.first else {
            throw KSError.configInvalid("config.windows is empty")
        }
        return first
    }

    /// 프론트엔드 제공 방식 결정. 세 가지 결과:
    ///   - `.virtualHost(root)`     — `https://app.kalsae/`(Windows) 또는
    ///                                `ks://app/`(macOS/Linux)로 로컬 자산 제공.
    ///   - `.devServer`             — `config.build.devServerURL`로 직접 전달.
    ///   - `.fallback`              — 가상 호스트도 라이브 dev 서버도 없음;
    ///                                호출자가 dev URL 문자열로 폴백.
    enum ServingMode: Sendable {
        case virtualHost(URL)
        case devServer
        case fallback
    }

    static func decideServingMode(
        urlOverride: String?,
        windowURL: String?,
        devServerURL: String,
        resourceRoot: URL?
    ) -> ServingMode {
        let devIsRemote = isRemoteURL(devServerURL)
        // 호출자/윈도우가 명시 URL을 안 줬고 dev 서버가 살아있으면 dev 우선.
        // release 빌드에서는 dev 서버 분기를 차단해 패키징 산출물이 우연히
        // `http://localhost:5173` 같은 잔존 dev URL 로 navigate 하지 않도록
        // 한다(잔존 시 Vite 부재 → `chrome-error://` → 흰 화면). 동일 보호는
        // `KSApp.boot` 의 `security.devtools` 강제 off 와 동일 신호(`#if !DEBUG`)를
        // 사용해 정책 일관성을 맞춘다.
        if urlOverride == nil, windowURL == nil, devIsRemote {
            #if DEBUG
                // DEBUG 에서도 dev 서버가 실제로 응답하지 않으면 가상 호스트로
                // 폴백한다. Vite 가 안 떠 있을 때 `chrome-error://` 가 뜨는
                // 흰 화면을 막는다. probe 가 200ms+슬랙 으로 짧기 때문에
                // 부팅 지연은 사실상 무시 가능.
                if isDevServerReachable(devServerURL) {
                    return .devServer
                }
                KSLog.logger("kalsae.app").warning(
                    "dev server unreachable at \(devServerURL); falling back to virtualHost/file"
                )
            #endif
            // release: 가상 호스트 / fallback 분기로 떨어진다.
        }
        if let resourceRoot, isDirectory(resourceRoot) {
            return .virtualHost(resourceRoot)
        }
        #if os(Windows)
            if KSEmbeddedAssetResolverFactory.shouldPreferEmbeddedAssets() {
                return .virtualHost(resourceRoot ?? URL(fileURLWithPath: "."))
            }
        #endif
        return .fallback
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
        if let urlOverride { return urlOverride }
        if let windowURL { return windowURL }
        switch servingMode {
        case .virtualHost:
            #if os(Windows)
                return "https://\(virtualHost)/index.html"
            #else
                // WebKit은 커스텀 스키마가 필요하다 — http/https에는 스키마
                // 핸들러를 등록할 수 없다. 크로스플랫폼에서 `ks://app/...`을 쓴다.
                return "ks://app/index.html"
            #endif
        case .devServer:
            return devServerURL
        case .fallback:
            return diagnosticDataURL(attemptedURL: devServerURL)
        }
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
