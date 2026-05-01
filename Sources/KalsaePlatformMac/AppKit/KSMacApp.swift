#if os(macOS)
internal import AppKit
internal import Logging
internal import KalsaeCore

/// 프로세스 전역 `NSApplication`을 감싸 mac 백엔드의 나머지 부분이
/// 라이프사이클을 알 필요가 없도록 한다. Windows 측
/// `Win32App`과 대응한다.
@MainActor
internal final class KSMacApp {
    static let shared = KSMacApp()

    private let log: Logger = KSLog.logger("platform.mac.app")
    private var initialized = false

    private init() {}

    /// 윈도우/웹뷰 생성 전에 메인 스레드에서 반드시 한 번 호출해야 한다. 멱등성 보장.
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

    /// `NSApplication.terminate(_:)`가 호출될 때까지 AppKit 이벤트 루프를
    /// 실행하며 호출 스레드를 블록한다.
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
