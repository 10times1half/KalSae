internal import Foundation
public import KalsaeCore

#if os(macOS)
internal import KalsaePlatformMac
#elseif os(Windows)
internal import KalsaePlatformWindows
#elseif os(Linux)
internal import KalsaePlatformLinux
#endif

extension KSApp {
    // MARK: - Boot phases
    //
    // boot(config:)에서 추출한 순수 함수 / 플랫폼별 사이드이펙트 헬퍼.
    // 각 헬퍼는 단일 부팅 단계를 캡슐화한다.

    /// Picks the window config to open for this boot. Returns the entry
    /// matching `label`, or — when `label` is `nil` — the first window
    /// declared in the config.
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

    /// Frontend serving decision. Three outcomes:
    ///   - `.virtualHost(root)`     — local assets via `https://app.kalsae/`
    ///                                (Windows) or `ks://app/` (macOS/Linux).
    ///   - `.devServer`             — pass-through to `config.build.devServerURL`.
    ///   - `.fallback`              — neither virtual host nor live dev server;
    ///                                caller falls back to the dev URL string.
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
        if urlOverride == nil, windowURL == nil, devIsRemote {
            return .devServer
        }
        if let resourceRoot, isDirectory(resourceRoot) {
            return .virtualHost(resourceRoot)
        }
        return .fallback
    }

    /// Resolves the actual URL string to load into the window, honouring
    /// (in order): per-call override → per-window URL → virtual-host
    /// default → live dev server → raw `devServerURL` fallback.
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
        case .devServer, .fallback:
            return devServerURL
        }
    }

    #if os(Windows)
    /// Wires `KSWindowsCommandRouter` clicks to (a) a `"menu"` event
    /// emitted to the frontend and (b) registry dispatch of any
    /// matching `@KSCommand` handler. Holds `app` weakly.
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

    /// Wires the Windows notification backend through the tray icon so
    /// toasts surface via the resident shell icon. Safe to call before
    /// `tray.install(...)` because `attachTray` stores a weak reference.
    static func bindNotificationsToTray(platform: any KSPlatform) {
        if let nbackend = platform.notifications as? KSWindowsNotificationBackend,
           let traybackend = platform.tray as? KSWindowsTrayBackend {
            nbackend.attachTray(traybackend)
        }
    }
    #endif
}
