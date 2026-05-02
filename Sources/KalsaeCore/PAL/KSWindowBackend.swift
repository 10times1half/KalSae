/// 단일 윈돈우에 요청된 시각적 테마 변형.
public import Foundation

/// 픽셀 단위 2D 크기.

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

/// 위치와 크기 조작.

/// 시각적/표시 상태: 제목, 최소화/최대화, 테마, 데코레이션.

/// 네이티브 윈돈우를 생성하고 추적하고 조작한다.
///
/// `KSWindowLifecycle`, `KSWindowGeometry`, `KSWindowState`를
/// 합성한 refinement이다. 백엔드는 이 단일 프로토콜을 철헌하고;
/// 일부 슬라이스만 필요한 소비자(예: 테스트)는
/// 더 좌은 결합을 위해 `any KSWindowGeometry`로 타입 소거할 수 있다.
///
/// 아직 구현되지 않은 메서드는 `KSError(code: .unsupportedPlatform)`를
/// 던지는 기본 구현을 상속한다.

// MARK: - Default implementations
//
// Phase-3에서 세 하위 프로토콜로 분할되었으므로, 기본 구현도 의미
// 단위로 따라 분할한다. 기존 플랫폼 스텁(`NotImplementedBackend`)이나
// 부분 구현 백엔드(예: 향후 macOS/Linux)에서 미구현 메서드는 그대로
// `unsupportedPlatform`을 던진다.

public enum KSWindowTheme: String, Codable, Sendable, CaseIterable {
    case light, dark, system
}
public struct KSSize: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
public protocol KSWindowLifecycle: Sendable {
    /// `config`에 따라 새 윈돈우를 생성한다. `config.visible == true`가 아닌
    /// 한 반환시 보이는 상태를 보장하지 않는다.
    func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle

    /// 주어진 윈돈우를 닫고 파괴한다.
    func close(_ handle: KSWindowHandle) async throws(KSError)

    func show(_ handle: KSWindowHandle) async throws(KSError)
    func hide(_ handle: KSWindowHandle) async throws(KSError)
    func focus(_ handle: KSWindowHandle) async throws(KSError)

    /// 주어진 윈돈우에 연결된 WebView를 반환한다.
    func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend

    /// 현재 라이브 상태인 모든 윈돈우를 열거한다.
    func all() async -> [KSWindowHandle]

    /// 사용자가 선언한 레이블로 윈돈우를 찾는다.
    func find(label: String) async -> KSWindowHandle?

    /// 임베디드 WebView의 현재 문서를 다시 로드한다.
    func reload(_ handle: KSWindowHandle) async throws(KSError)
}
public protocol KSWindowGeometry: Sendable {
    func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError)
    func setPosition(_ handle: KSWindowHandle, x: Int, y: Int) async throws(KSError)
    func getPosition(_ handle: KSWindowHandle) async throws(KSError) -> KSPoint
    func getSize(_ handle: KSWindowHandle) async throws(KSError) -> KSSize
    func setMinSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError)
    func setMaxSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError)
    func center(_ handle: KSWindowHandle) async throws(KSError)
}
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

    /// OS 닫기 버튼 인터셉터를 활성화/비활성화한다. 활성화 시
    /// 닫기 버튼 클릭은 `__ks.window.beforeClose` JS 이벤트를
    /// 발생시키고 앱이 명시적으로 닫을 때까지 윈돈우는 열린 상태를
    /// 유지한다.
    func setCloseInterceptor(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError)

    /// WebView 컨트롤러 줄 팩터를 설정한다(`1.0`이 원본).
    /// 범위를 벗어나는 값은 플랫폼 엔진에 의해 클램프된다.
    func setZoomFactor(_ handle: KSWindowHandle, factor: Double) async throws(KSError)

    /// 현재 WebView 컨트롤러 줄 팩터를 읽는다.
    func getZoomFactor(_ handle: KSWindowHandle) async throws(KSError) -> Double

    /// 윈돈우의 WebView에 대한 플랫폼 인쇄 UI를 연다. 최선 노력으로.
    /// `systemDialog == true`는 OS 시스템 인쇄 다이얼로그를 요청하고;
    /// 그렇지 않으면 엔진의 내장 미리보기 서페이스를 사용한다.
    func showPrintUI(_ handle: KSWindowHandle, systemDialog: Bool) async throws(KSError)

    /// 현재 WebView 콘텐츠를 인코딩된 이미지 바이트로 캡첸한다.
    /// `format == 0`이면 PNG, `format == 1`이면 JPEG를 반환한다. 다른
    /// 값은 PNG로 처리된다.
    func capturePreview(_ handle: KSWindowHandle, format: Int32) async throws(KSError) -> Data
}
public protocol KSWindowBackend:
    KSWindowLifecycle, KSWindowGeometry, KSWindowState
{}
@inline(__always)
private func _unsupportedThrow(_ op: String) throws(KSError) -> Never {
    throw KSError(
        code: .unsupportedPlatform,
        message: "KSWindowBackend.\(op) is not implemented on this platform.")
}
extension KSWindowLifecycle {
    public func reload(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("reload") }
}
extension KSWindowGeometry {
    public func setPosition(_ handle: KSWindowHandle, x: Int, y: Int) async throws(KSError) {
        try _unsupportedThrow("setPosition")
    }
    public func getPosition(_ handle: KSWindowHandle) async throws(KSError) -> KSPoint {
        try _unsupportedThrow("getPosition")
    }
    public func getSize(_ handle: KSWindowHandle) async throws(KSError) -> KSSize { try _unsupportedThrow("getSize") }
    public func setMinSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
        try _unsupportedThrow("setMinSize")
    }
    public func setMaxSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
        try _unsupportedThrow("setMaxSize")
    }
    public func center(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("center") }
}
extension KSWindowState {
    public func minimize(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("minimize") }
    public func maximize(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("maximize") }
    public func restore(_ handle: KSWindowHandle) async throws(KSError) { try _unsupportedThrow("restore") }
    public func toggleMaximize(_ handle: KSWindowHandle) async throws(KSError) {
        try _unsupportedThrow("toggleMaximize")
    }
    public func isMinimized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
        try _unsupportedThrow("isMinimized")
    }
    public func isMaximized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
        try _unsupportedThrow("isMaximized")
    }
    public func isFullscreen(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
        try _unsupportedThrow("isFullscreen")
    }
    public func setFullscreen(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
        try _unsupportedThrow("setFullscreen")
    }
    public func setAlwaysOnTop(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
        try _unsupportedThrow("setAlwaysOnTop")
    }
    public func setTheme(_ handle: KSWindowHandle, theme: KSWindowTheme) async throws(KSError) {
        try _unsupportedThrow("setTheme")
    }
    public func setBackgroundColor(_ handle: KSWindowHandle, rgba: UInt32) async throws(KSError) {
        try _unsupportedThrow("setBackgroundColor")
    }
    public func setCloseInterceptor(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
        try _unsupportedThrow("setCloseInterceptor")
    }
    public func setZoomFactor(_ handle: KSWindowHandle, factor: Double) async throws(KSError) {
        try _unsupportedThrow("setZoomFactor")
    }
    public func getZoomFactor(_ handle: KSWindowHandle) async throws(KSError) -> Double {
        try _unsupportedThrow("getZoomFactor")
    }
    public func showPrintUI(_ handle: KSWindowHandle, systemDialog: Bool) async throws(KSError) {
        try _unsupportedThrow("showPrintUI")
    }
    public func capturePreview(_ handle: KSWindowHandle, format: Int32) async throws(KSError) -> Data {
        try _unsupportedThrow("capturePreview")
    }
}
