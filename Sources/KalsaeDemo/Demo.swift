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

    // MARK: - Entry point

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
            let configURL = try resolveConfigURL()
            let resourceRoot = configURL.deletingLastPathComponent()
            print("Config:       \(configURL.path)")
            print("ResourceRoot: \(resourceRoot.path)")

            let app = try await KSApp.boot(
                configURL: configURL,
                resourceRoot: resourceRoot
            ) { registry in
                // @KSCommand로 생성된 등록 코드.
                await _ksRegister_greet(into: registry)
                await _ksRegister_ping(into: registry)
            }

            print("Booted \(app.config.app.name) v\(app.config.app.version)")
            print("Platform: \(app.platform.name)")

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
                    .action(id: "tray.notify", label: "Show Notification", command: "app.notify"),
                    .action(id: "tray.info", label: "About", command: "app.showInfo"),
                    .separator(),
                    .action(id: "tray.quit", label: "Quit", command: "app.quit"),
                ],
                onLeftClick: "app.showInfo")
            if (try? await tray.install(cfg)) == nil {
                print("Tray not supported on \(app.platform.name) yet; continuing without tray.")
            }
        }

        // MARK: - Config bootstrap

        @MainActor
        static func resolveConfigURL() throws -> URL {
            if let bundled = Bundle.module.url(
                forResource: "kalsae", withExtension: "json")
            {
                return bundled
            }
            throw KSError.configNotFound("kalsae.json (Demo bundle)")
        }
    }

#else

    @main
    struct Demo {
        static func main() {
            print("Kalsae \(Kalsae.version) — demo requires Windows, macOS, or Linux.")
        }
    }

#endif
