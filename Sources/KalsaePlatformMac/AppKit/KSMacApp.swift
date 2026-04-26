#if os(macOS)
internal import AppKit
internal import Logging
internal import KalsaeCore

/// Wraps the process-global `NSApplication` so that the rest of the mac
/// backend doesn't have to know about its lifecycle. Mirrors
/// `Win32App` on the Windows side.
@MainActor
internal final class KSMacApp {
    static let shared = KSMacApp()

    private let log: Logger = KSLog.logger("platform.mac.app")
    private var initialized = false

    private init() {}

    /// Must be called on the main thread before any window / webview is
    /// created. Idempotent.
    func ensureInitialized() {
        guard !initialized else { return }
        // `NSApplication.shared`를 참조하면 공유 앱이 지연 생성된다.
        let app = NSApplication.shared
        // `.regular`은 프로세스를 일반 GUI 앱(동 아이콘, 메뉴바 등)으로
        // 승격시킨다. 메뉴바 전용(`.accessory`) 또는 백그라운드
        // (`.prohibited`) 앱을 원하는 소비자는 부팅 이후 재설정하면 된다.
        app.setActivationPolicy(.regular)
        initialized = true
        log.info("NSApplication initialized with activation policy .regular")
    }

    /// Blocks the calling thread running the AppKit event loop until
    /// `NSApplication.terminate(_:)` is invoked.
    func runMessageLoop() -> Int32 {
        let app = NSApplication.shared
        app.activate(ignoringOtherApps: true)
        log.info("Entering NSApplication.run()")
        app.run()
        log.info("NSApplication.run() returned")
        return 0
    }
}
#endif
