import Foundation

/// Visual theme variant requested for a single window.
public enum KSWindowTheme: String, Codable, Sendable, CaseIterable {
    case light, dark, system
}

/// 2D size in pixels.
public struct KSSize: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

// MARK: - Sub-protocols (Phase 3 split)
//
// 원본 `KSWindowBackend`은 25개의 메서드를 한 프로토콜에 묶어 두어
// 각 책임 영역(생성/삭제 vs 기하 vs 상태)이 시각적으로 섞여 있었다.
// 의미 단위로 세 하위 프로토콜로 분할하고, `KSWindowBackend`는 이
// 세 프로토콜을 합성한 refinement로 정의한다. 기존 구현(`KSWindowsWindowBackend`,
// `NotImplementedBackend`)과 모든 호출처(`platform.windows`)는 변경 없이
// 컴파일된다 — refinement는 ABI/소스 호환이다.
//
// 합성된 정의를 의도적으로 노출해 두어, 향후 통합 테스트가 특정
// 책임 영역만 허약하게 모킹할 수 있다(`any KSWindowGeometry`).

/// Window creation, identification, visibility, and webview attachment.
public protocol KSWindowLifecycle: Sendable {
    /// Creates a new window according to `config`. The window is not
    /// guaranteed to be visible on return unless `config.visible == true`.
    func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle

    /// Closes and destroys the given window.
    func close(_ handle: KSWindowHandle) async throws(KSError)

    func show(_ handle: KSWindowHandle) async throws(KSError)
    func hide(_ handle: KSWindowHandle) async throws(KSError)
    func focus(_ handle: KSWindowHandle) async throws(KSError)

    /// Returns the webview attached to the given window.
    func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend

    /// Enumerates all currently live windows.
    func all() async -> [KSWindowHandle]

    /// Finds a window by its user-declared label.
    func find(label: String) async -> KSWindowHandle?

    /// Reloads the embedded webview's current document.
    func reload(_ handle: KSWindowHandle) async throws(KSError)
}

/// Position and size manipulation.
public protocol KSWindowGeometry: Sendable {
    func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError)
    func setPosition(_ handle: KSWindowHandle, x: Int, y: Int) async throws(KSError)
    func getPosition(_ handle: KSWindowHandle) async throws(KSError) -> KSPoint
    func getSize(_ handle: KSWindowHandle) async throws(KSError) -> KSSize
    func setMinSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError)
    func setMaxSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError)
    func center(_ handle: KSWindowHandle) async throws(KSError)
}

/// Visual / display state: title, minimize/maximize, theming, decoration.
public protocol KSWindowState: Sendable {
    func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError)
    func minimize(_ handle: KSWindowHandle) async throws(KSError)
    func maximize(_ handle: KSWindowHandle) async throws(KSError)
    func restore(_ handle: KSWindowHandle) async throws(KSError)
    func toggleMaximize(_ handle: KSWindowHandle) async throws(KSError)
    func isMinimized(_ handle: KSWindowHandle) async throws(KSError) -> Bool
    func isMaximized(_ handle: KSWindowHandle) async throws(KSError) -> Bool
    func isFullscreen(_ handle: KSWindowHandle) async throws(KSError) -> Bool
    func setFullscreen(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError)
    func setAlwaysOnTop(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError)
    func setTheme(_ handle: KSWindowHandle, theme: KSWindowTheme) async throws(KSError)
    func setBackgroundColor(_ handle: KSWindowHandle, rgba: UInt32) async throws(KSError)

    /// Enables/disables the OS close button interceptor. When enabled,
    /// pressing the close button emits a `__ks.window.beforeClose` JS
    /// event and the window stays open until the app explicitly closes it.
    func setCloseInterceptor(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError)
}

/// Creates, tracks, and manipulates native windows.
///
/// This is the composite refinement of `KSWindowLifecycle`,
/// `KSWindowGeometry`, and `KSWindowState`. Backends conform to this
/// single protocol; consumers that only need a slice (e.g. tests) may
/// type-erase to `any KSWindowGeometry` for narrower coupling.
///
/// Methods that a particular platform hasn't implemented yet inherit a
/// default implementation that throws `KSError(code: .unsupportedPlatform)`.
public protocol KSWindowBackend:
    KSWindowLifecycle, KSWindowGeometry, KSWindowState
{}

// MARK: - Default implementations
//
// Phase-3에서 세 하위 프로토콜로 분할되었으므로, 기본 구현도 의미
// 단위로 따라 분할한다. 기존 플랫폼 스텁(`NotImplementedBackend`)이나
// 부분 구현 백엔드(예: 향후 macOS/Linux)에서 미구현 메서드는 그대로
// `unsupportedPlatform`을 던진다.

@inline(__always)
private func _unsupportedThrow(_ op: String) throws(KSError) -> Never {
    throw KSError(code: .unsupportedPlatform,
                  message: "KSWindowBackend.\(op) is not implemented on this platform.")
}

extension KSWindowLifecycle {
    public func reload(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("reload") }
}

extension KSWindowGeometry {
    public func setPosition(_ handle: KSWindowHandle, x: Int, y: Int) async throws(KSError) { try _unsupportedThrow("setPosition") }
    public func getPosition(_ handle: KSWindowHandle) async throws(KSError) -> KSPoint { try _unsupportedThrow("getPosition") }
    public func getSize(_ handle: KSWindowHandle) async throws(KSError) -> KSSize { try _unsupportedThrow("getSize") }
    public func setMinSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) { try _unsupportedThrow("setMinSize") }
    public func setMaxSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) { try _unsupportedThrow("setMaxSize") }
    public func center(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("center") }
}

extension KSWindowState {
    public func minimize(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("minimize") }
    public func maximize(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("maximize") }
    public func restore(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("restore") }
    public func toggleMaximize(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("toggleMaximize") }
    public func isMinimized(_ handle: KSWindowHandle) async throws(KSError) -> Bool { try _unsupportedThrow("isMinimized") }
    public func isMaximized(_ handle: KSWindowHandle) async throws(KSError) -> Bool { try _unsupportedThrow("isMaximized") }
    public func isFullscreen(_ handle: KSWindowHandle) async throws(KSError) -> Bool { try _unsupportedThrow("isFullscreen") }
    public func setFullscreen(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) { try _unsupportedThrow("setFullscreen") }
    public func setAlwaysOnTop(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) { try _unsupportedThrow("setAlwaysOnTop") }
    public func setTheme(_ handle: KSWindowHandle, theme: KSWindowTheme) async throws(KSError) { try _unsupportedThrow("setTheme") }
    public func setBackgroundColor(_ handle: KSWindowHandle, rgba: UInt32) async throws(KSError) { try _unsupportedThrow("setBackgroundColor") }
    public func setCloseInterceptor(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) { try _unsupportedThrow("setCloseInterceptor") }
}
