// KalsaeDemo/Demo.swift — @KSCommand IPC 계층 위에 메뉴·트레이·알림을
// 연결한 Phase 8 스모크 테스트 코드.

import Foundation
import Kalsae

#if os(Windows) || os(macOS) || os(Linux)

    // MARK: - @KSCommand functions (regular IPC callables)

    struct GreetOut: Codable, Sendable { let message: String }

    @KSCommand
    func greet(name: String?) -> GreetOut {
        GreetOut(message: "Hello, \(name ?? "World")!")
    }

    struct PingOut: Codable, Sendable {
        let pong: Bool
        let at: TimeInterval
    }

    @KSCommand
    func ping() -> PingOut {
        PingOut(pong: true, at: Date().timeIntervalSince1970)
    }

    // MARK: - Phase 1-5 IPC arg types

    struct CtxMenuArgs: Codable, Sendable {
        let x: Double
        let y: Double
    }

    struct EnabledArg: Codable, Sendable {
        let enabled: Bool
    }

    // MARK: - Entry point

    /// 단일 인스턴스 콜백과 부팅된 `KSApp`을 연결하는 작은 라우터.
    /// `KSApp.singleInstance`는 `boot(...)` **전에** 호출해야 하지만
    /// argv는 부팅된 `app`에서만 처리할 수 있다. 부팅 전 도착한 argv는
    /// 보관해 두었다가 `bind(app)`에서 흘려보낸다.
    @MainActor
    final class DeepLinkRouter {
        private var app: KSApp?
        private var pending: [[String]] = []
        func receive(_ args: [String]) {
            if let app {
                app.dispatchDeepLinkURLs(args: args)
            } else {
                pending.append(args)
            }
        }
        func bind(_ app: KSApp) {
            self.app = app
            for args in pending {
                app.dispatchDeepLinkURLs(args: args)
            }
            pending.removeAll()
        }
    }

    @main
    struct Demo {
        static func main() async {
            print("Kalsae \(Kalsae.version) — demo")
            do {
                try await run()
            } catch {
                print("Demo failed: \(error)")
            }
        }

        @MainActor
        static func run() async throws {
            let resolved = KSApp.resolveBundledConfigURL(resourceBundle: .module)
            let configURL = resolved.url
            print("Config:       \(configURL.path)")
            if let r = resolved.resourceRoot {
                print("ResourceRoot: \(r.path)")
            } else {
                print("ResourceRoot: <auto: configDir + config.build.frontendDist>")
            }

            // 단일 인스턴스 + 딥링크 라우터.
            // 두 번째 실행은 argv를 기본 인스턴스에 전달한 뒤 종료한다.
            // 기본 인스턴스는 도착한 argv를 `dispatchDeepLinkURLs`로 흘려
            // `__ks.deepLink.openURL` 이벤트를 발생시킨다.
            let router = DeepLinkRouter()
            switch KSApp.singleInstance(identifier: "dev.kalsae.demo") { args in
                router.receive(args)
            } {
            case .relayed:
                print("Another instance is primary; relayed args and exiting.")
                return
            case .primary:
                break
            }

            let app = try await KSApp.boot(
                configURL: configURL,
                resourceRoot: resolved.resourceRoot
            ) { registry in
                // @KSCommand로 생성된 등록 코드.
                await _ksRegister_greet(into: registry)
                await _ksRegister_ping(into: registry)
            }

            // 부팅 직후 라우터를 바인딩하고 자기 자신의 argv를 한 번 흘려
            // (예: `kalsae-demo.exe kalsae-demo://hello`로 직접 기동된 경우)
            // 페이지가 첫 URL을 관찰할 수 있도록 한다.
            router.bind(app)
            app.dispatchDeepLinkURLs(args: CommandLine.arguments)

            print("Booted \(app.config.app.name) v\(app.config.app.version)")
            print("Platform: \(app.platform.name)")
            print("PAL capabilities:")
            print("  tray:         \(app.platform.tray != nil)")
            print("  accelerators: \(app.platform.accelerators != nil)")
            print("  autostart:    \(app.platform.autostart != nil)")
            print("  deepLink:     \(app.platform.deepLink != nil)")

            // 메뉴 / 트레이에서 구동되는 액션. 부팅 이후에 등록해서 클로저가
            // `app`을 직접 캡처할 수 있도록 한다. 핸들러 내부에서 다른 `@MainActor`
            // 홀더에서 읽으면 GetMessageW 데드락(차단된 메인 스레드로의 협동 홉)이
            // 다시 생긴다.
            await app.registry.register("app.showInfo") { [app] _ in
                app.showMessage(
                    KSMessageOptions(
                        kind: .info,
                        title: "Kalsae",
                        message: "Hello from a native dialog.",
                        detail: "Kalsae \(Kalsae.version) — \(app.platform.name)",
                        buttons: .ok))
                return .success(Data("{}".utf8))
            }
            await app.registry.register("app.openFile") { [app] _ in
                app.openFile(
                    KSOpenFileOptions(
                        title: "Pick a file",
                        filters: [
                            KSFileFilter(name: "Text", extensions: ["txt", "md"]),
                            KSFileFilter(name: "All Files", extensions: ["*"]),
                        ],
                        allowsMultiple: false)
                ) { urls in
                    struct Payload: Encodable { let paths: [String] }
                    try? app.emit(
                        "openFile.result",
                        payload: Payload(paths: urls.map(\.path)))
                }
                return .success(Data("{}".utf8))
            }
            await app.registry.register("app.notify") { [app] _ in
                let n = KSNotification(
                    id: "demo.notify.\(Int(Date().timeIntervalSince1970))",
                    title: "Kalsae",
                    body: "This is a native toast posted from Swift.")
                app.postNotification(n)
                return .success(Data("{}".utf8))
            }
            await app.registry.register("app.quit") { [app] _ in
                app.quit()
                return .success(Data("{}".utf8))
            }

            // Show/hide the main window. **Recursive registry dispatch
            // (`await app.registry.dispatch("__ks.window.show")`) hangs on
            // actor reentrancy when invoked from another registry handler
            // — call the platform window backend directly instead.**
            await app.registry.register("app.showWindow") { [app] _ in
                let windows = app.platform.windows
                guard let h = await windows.all().first else {
                    return .success(Data("{}".utf8))
                }
                try? await windows.show(h)
                return .success(Data("{}".utf8))
            }
            await app.registry.register("app.hideWindow") { [app] _ in
                let windows = app.platform.windows
                guard let h = await windows.all().first else {
                    return .success(Data("{}".utf8))
                }
                try? await windows.hide(h)
                return .success(Data("{}".utf8))
            }

            // Native context menu. JS calls this from `oncontextmenu` with the
            // click coordinates; the menu items reuse the existing app.* commands.
            await app.registry.register("app.contextMenu") { [app] data in
                let args: CtxMenuArgs
                do {
                    args = try JSONDecoder().decode(CtxMenuArgs.self, from: data)
                } catch {
                    return .failure(
                        KSError(
                            code: .commandDecodeFailed,
                            message: "app.contextMenu expects {x, y}"))
                }
                let items: [KSMenuItem] = [
                    .action(
                        id: "ctx.notify", label: "Show Notification",
                        command: "app.notify"),
                    .action(
                        id: "ctx.info", label: "About", command: "app.showInfo"),
                    .separator(),
                    .action(
                        id: "ctx.hide", label: "Hide Window",
                        command: "app.hideWindow"),
                    .action(
                        id: "ctx.quit", label: "Quit", command: "app.quit"),
                ]
                do {
                    try await app.platform.menus.showContextMenu(
                        items,
                        at: KSPoint(x: args.x, y: args.y),
                        in: nil)
                    return .success(Data("{}".utf8))
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(
                                code: .commandExecutionFailed,
                                message: "app.contextMenu: \(error)"))
                }
            }

            // Toggle a global hot-key (Ctrl+Shift+K) that fires a notification.
            // Demonstrates `app.platform.accelerators` (Windows-only today).
            await app.registry.register("app.toggleAccelerator") { [app] data in
                guard let accels = app.platform.accelerators else {
                    return .failure(
                        KSError(
                            code: .unsupportedPlatform,
                            message:
                                "accelerators not available on \(app.platform.name)"
                        ))
                }
                let args: EnabledArg
                do {
                    args = try JSONDecoder().decode(EnabledArg.self, from: data)
                } catch {
                    return .failure(
                        KSError(
                            code: .commandDecodeFailed,
                            message: "app.toggleAccelerator expects {enabled}"))
                }
                do {
                    if args.enabled {
                        try await accels.register(
                            id: "demo.hotkey",
                            accelerator: "Ctrl+Shift+K"
                        ) { [weak app] in
                            guard let app else { return }
                            let n = KSNotification(
                                id:
                                    "demo.hotkey.\(Int(Date().timeIntervalSince1970))",
                                title: "Kalsae",
                                body: "Ctrl+Shift+K fired")
                            app.postNotification(n)
                        }
                    } else {
                        try await accels.unregister(id: "demo.hotkey")
                    }
                    return .success(Data("{}".utf8))
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(
                                code: .commandExecutionFailed,
                                message: "app.toggleAccelerator: \(error)"))
                }
            }

            try await installMenus(app: app)
            try await installTray(app: app)

            // 프론트에 실시간 이벤트를 제공하기 위한 백그라운드 틱 스트림.
            let tickTask = Task.detached { [weak app] in
                struct Tick: Encodable {
                    let n: Int
                    let at: TimeInterval
                }
                var n = 0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    n += 1
                    let payload = Tick(n: n, at: Date().timeIntervalSince1970)
                    app?.postJob { [weak app] in
                        try? app?.emit("tick", payload: payload)
                    }
                }
            }

            _ = app.run()
            tickTask.cancel()
        }

        // MARK: - Menu / tray installation

        @MainActor
        static func installMenus(app: KSApp) async throws {
            let fileMenu = KSMenuItem.submenu(
                id: "file", label: "File",
                items: [
                    .action(id: "info", label: "Show Info Dialog", accelerator: "CmdOrCtrl+I", command: "app.showInfo"),
                    .action(id: "open", label: "Open File…", accelerator: "CmdOrCtrl+O", command: "app.openFile"),
                    .action(
                        id: "notify", label: "Show Notification", accelerator: "CmdOrCtrl+N", command: "app.notify"),
                    .separator(),
                    .action(id: "quit", label: "Quit", accelerator: "Alt+F4", command: "app.quit"),
                ])
            let helpMenu = KSMenuItem.submenu(
                id: "help", label: "Help",
                items: [
                    .action(id: "about", label: "About Kalsae", command: "app.showInfo")
                ])
            if (try? await app.platform.menus.installAppMenu([fileMenu, helpMenu])) == nil {
                print("App menu not supported on \(app.platform.name) yet; continuing without menu.")
            }
        }

        @MainActor
        static func installTray(app: KSApp) async throws {
            guard let tray = app.platform.tray else {
                print("Tray not supported on this platform.")
                return
            }
            let cfg = KSTrayConfig(
                icon: "",  // empty → falls back to stock icon on Windows
                tooltip: "Kalsae Demo",
                menu: [
                    .action(
                        id: "tray.show", label: "Show Window",
                        command: "app.showWindow"),
                    .action(
                        id: "tray.hide", label: "Hide Window",
                        command: "app.hideWindow"),
                    .separator(),
                    .action(id: "tray.notify", label: "Show Notification", command: "app.notify"),
                    .action(id: "tray.info", label: "About", command: "app.showInfo"),
                    .separator(),
                    .action(id: "tray.quit", label: "Quit", command: "app.quit"),
                ],
                onLeftClick: "app.showWindow")
            if (try? await tray.install(cfg)) == nil {
                print("Tray not supported on \(app.platform.name) yet; continuing without tray.")
            }
        }

        // MARK: - Config bootstrap

        // 자체 `resolveConfigURL()` 헬퍼는 Phase 2에서 `KSApp.resolveBundledConfigURL`
        // 으로 통합되어 제거되었다.
    }

#else

    @main
    struct Demo {
        static func main() {
            print("Kalsae \(Kalsae.version) — demo requires Windows, macOS, or Linux.")
        }
    }

#endif
