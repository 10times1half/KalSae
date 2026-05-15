public import Foundation

/// JS 프론트엔드와 Swift IPC 코어(`KSCommandRegistry`)를 연결하는 플랫폼별
/// 브리지의 공통 추상화.
///
/// 각 WebView 엔진마다 정확히 하나의 구체 구현이 존재한다:
/// - Windows: `WebView2Bridge` (`KalsaePlatformWindows`)
/// - macOS: `WKBridge` (`KalsaePlatformMac`)
/// - Linux: `GtkBridge` (`KalsaePlatformLinux`)
/// - iOS: `KSiOSBridge` (`KalsaePlatformIOS`)
/// - Android: `KSAndroidBridge` (`KalsaePlatformAndroid`)
///
/// 실질적인 처리(와이어 디코드, 디스패치, 응답 인코드, 정책 평가)는
/// `KSIPCBridgeCore`에 있어 플랫폼 간 동일하다. `KSBridge` 채택 타입은
/// WebView 호스트와 IPC 코어를 연결하는 얇은 배관만 담당한다.
///
/// `KSDemoHost` 구현은 `var bridge: any KSBridge { get }`을 통해 이 추상화를
/// 노출하므로 KalsaeCore 레벨의 코드(예: 플러그인, 통합 테스트)가 플랫폼
/// 분기 없이 emit/listen을 사용할 수 있다.
@MainActor
public protocol KSBridge: AnyObject, Sendable {
    /// 이 브리지가 묶인 윈도우 식별자 (`KSWindowConfig.label`).
    var windowLabel: String { get }

    /// JS 측 `emit` 메시지를 Swift에서 수신하는 싱크.
    ///
    /// JS frontend가 `window.__KS_.emit(name, payload)`를 호출하면 이 클로저가
    /// MainActor에서 호출된다. `nil`로 설정하면 수신을 중단한다.
    var onEvent: (@MainActor (_ name: String, _ payload: Data?) -> Void)? { get set }

    /// 호스트의 메시지 수신기를 설치한다. WebView가 준비된 직후 정확히
    /// 한 번 호출되어야 한다. 중복 호출 시 동작은 구현 정의(현재 모든
    /// 구현은 안전하게 마지막 호출만 유지).
    func install() throws(KSError)

    /// JS frontend에 이벤트를 발행한다 (`window.__KS_.listen(name, cb)`).
    ///
    /// - Parameters:
    ///   - name: 이벤트 이름. `__ks.` prefix는 KalSae 내장용으로 예약되어
    ///     있으므로 사용자 이벤트는 다른 prefix를 사용해야 한다.
    ///   - payload: `Encodable`로 직렬화 가능한 페이로드.
    func emit(event name: String, payload: any Encodable) throws(KSError)
}
