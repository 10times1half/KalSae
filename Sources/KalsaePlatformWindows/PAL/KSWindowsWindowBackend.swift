#if os(Windows)
internal import WinSDK
public import KalsaeCore
public import Foundation

/// Windows implementation of `KSWindowBackend`.
///
/// Operates on the set of `Win32Window` instances tracked by `Win32App`
/// and `KSWin32HandleRegistry`. The `KSWindowsDemoHost`'s primary
/// window is registered through that path, so all of the state APIs
/// (minimize/maximize/center/setPosition/setAlwaysOnTop/...) work
/// against it out of the box.
///
/// `create(_:)` and `webView(for:)` for newly-created windows currently
/// throw `unsupportedPlatform` — fully wiring multi-window WebView2
/// initialization (each window owning its own `WebView2Host` and bridge)
/// is the next milestone. All other operations are functional today.
public struct KSWindowsWindowBackend: KSWindowBackend, Sendable {
    public init() {}

    // MARK: - Resolution helpers

    @MainActor
    private func window(for handle: KSWindowHandle) throws(KSError) -> Win32Window {
        guard let hwnd = KSWin32HandleRegistry.shared.hwnd(for: handle) else {
            throw KSError(code: .windowCreationFailed,
                          message: "No window registered for label '\(handle.label)'")
        }
        guard let win = Win32App.shared.window(for: hwnd) else {
            throw KSError(code: .windowCreationFailed,
                          message: "Win32Window not tracked for label '\(handle.label)'")
        }
        return win
    }

    @MainActor
    private func handle(of window: Win32Window) -> KSWindowHandle? {
        guard let hwnd = window.hwnd else { return nil }
        let raw = UInt64(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd))))
        return KSWindowHandle(label: window.label, rawValue: raw)
    }

    // MARK: - Lifecycle

    public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
        // 멀티 윈도우 Win32 + WebView2는 다음 마일스톤. 지금은 단일
        // "main" 윈도우만 `KSWindowsDemoHost`를 통해 생성한다.
        throw KSError(
            code: .unsupportedPlatform,
            message: "KSWindowsWindowBackend.create lands together with multi-window WebView2 wiring. Use KSWindowsDemoHost to create the primary window in this release.")
    }

    public func close(_ handle: KSWindowHandle) async throws(KSError) {
        let result: Result<Void, KSError> = await MainActor.run {
            // `MainActor.run` 클로저 내부는 typed-throws 추론이 적용되지
            // 않으므로 `as? KSError`로 명시 캐스팅한다. window(for:)는
            // KSError만 엔젯한다.
            do {
                let w = try self.window(for: handle)
                w.close()
                return .success(())
            } catch {
                return .failure(error as? KSError
                    ?? KSError(code: .internal, message: "\(error)"))
            }
        }
        try result.unwrap()
    }

    public func show(_ handle: KSWindowHandle) async throws(KSError) {
        try await runMain(handle) { $0.show() }
    }

    public func hide(_ handle: KSWindowHandle) async throws(KSError) {
        try await runMain(handle) { $0.hide() }
    }

    public func focus(_ handle: KSWindowHandle) async throws(KSError) {
        try await runMain(handle) { $0.focus() }
    }

    public func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {
        try await runMain(handle) { $0.setTitle(title) }
    }

    public func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
        try await runMain(handle) { $0.setSize(width: width, height: height) }
    }

    public func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend {
        // 윈도우별 WebView 접근자는 멀티 윈도우 마일스톤에서 함께 구현된다
        // — 위 `create(_:)` 참조.
        throw KSError(
            code: .unsupportedPlatform,
            message: "KSWindowsWindowBackend.webView(for:) lands with multi-window WebView2 wiring.")
    }

    public func all() async -> [KSWindowHandle] {
        await MainActor.run {
            Win32App.shared.allWindows().compactMap { handle(of: $0) }
        }
    }

    public func find(label: String) async -> KSWindowHandle? {
        await MainActor.run {
            KSWin32HandleRegistry.shared.handle(for: label)
        }
    }

    // MARK: - State (Phase 1 extensions)

    public func minimize(_ handle: KSWindowHandle) async throws(KSError) {
        try await runMain(handle) { $0.minimize() }
    }

    public func maximize(_ handle: KSWindowHandle) async throws(KSError) {
        try await runMain(handle) { $0.maximize() }
    }

    public func restore(_ handle: KSWindowHandle) async throws(KSError) {
        try await runMain(handle) { $0.restore() }
    }

    public func toggleMaximize(_ handle: KSWindowHandle) async throws(KSError) {
        try await runMain(handle) { $0.toggleMaximize() }
    }

    public func isMinimized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
        try await queryMain(handle) { $0.isMinimized() }
    }

    public func isMaximized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
        try await queryMain(handle) { $0.isMaximized() }
    }

    public func isFullscreen(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
        try await queryMain(handle) { $0.isFullscreen() }
    }

    public func setFullscreen(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
        try await runMain(handle) { $0.setFullscreen(enabled) }
    }

    public func setAlwaysOnTop(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
        try await runMain(handle) { $0.setAlwaysOnTop(enabled) }
    }

    public func center(_ handle: KSWindowHandle) async throws(KSError) {
        try await runMain(handle) { $0.centerOnScreen() }
    }

    public func setPosition(_ handle: KSWindowHandle, x: Int, y: Int) async throws(KSError) {
        try await runMain(handle) { $0.setPosition(x: x, y: y) }
    }

    public func getPosition(_ handle: KSWindowHandle) async throws(KSError) -> KSPoint {
        try await queryMain(handle) {
            let p = $0.getPosition()
            return KSPoint(x: Double(p.x), y: Double(p.y))
        }
    }

    public func getSize(_ handle: KSWindowHandle) async throws(KSError) -> KSSize {
        try await queryMain(handle) {
            let s = $0.getSize()
            return KSSize(width: s.width, height: s.height)
        }
    }

    public func setMinSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
        try await runMain(handle) { $0.setMinSize(width: width, height: height) }
    }

    public func setMaxSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
        try await runMain(handle) { $0.setMaxSize(width: width, height: height) }
    }

    public func reload(_ handle: KSWindowHandle) async throws(KSError) {
        try await runMain(handle) { $0.reload() }
    }

    public func setTheme(_ handle: KSWindowHandle, theme: KSWindowTheme) async throws(KSError) {
        try await runMain(handle) { $0.setTheme(theme) }
    }

    public func setBackgroundColor(_ handle: KSWindowHandle, rgba: UInt32) async throws(KSError) {
        try await runMain(handle) { $0.setBackgroundColor(rgba: rgba) }
    }

    public func setCloseInterceptor(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
        try await runMain(handle) { $0.setCloseInterceptor(enabled) }
    }

    // MARK: - Internals

    private func runMain(
        _ handle: KSWindowHandle,
        _ body: @MainActor @Sendable (Win32Window) -> Void
    ) async throws(KSError) {
        let result: Result<Void, KSError> = await MainActor.run {
            do {
                let w = try self.window(for: handle)
                body(w)
                return .success(())
            } catch {
                return .failure(error as? KSError
                    ?? KSError(code: .internal, message: "\(error)"))
            }
        }
        try result.unwrap()
    }

    private func queryMain<T: Sendable>(
        _ handle: KSWindowHandle,
        _ body: @MainActor @Sendable (Win32Window) -> T
    ) async throws(KSError) -> T {
        let result: Result<T, KSError> = await MainActor.run {
            do {
                let w = try self.window(for: handle)
                return .success(body(w))
            } catch {
                return .failure(error as? KSError
                    ?? KSError(code: .internal, message: "\(error)"))
            }
        }
        return try result.unwrap()
    }
}
#endif
