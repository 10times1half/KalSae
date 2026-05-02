/// WKWebView / WebView2 / WebKitGTK를 추상화한다.
public import Foundation

public protocol KSWebViewBackend: Sendable {
    /// 절대 URL을 로드한다. 릴리스 빌드에서는 보통 스킴
    /// 핸들러가 제공하는 `ks://localhost/...` URL이다.
    func load(url: URL) async throws(KSError)

    /// 메인 프레임에서 JS 표현식을 평가한다. 표현식이 값을 생성하면 JSON으로,
    /// `undefined`/`null`이면 `nil`로 반환한다.
    @discardableResult
    func evaluateJavaScript(_ source: String) async throws(KSError) -> Data?

    /// 구조화된 메시지를 JS 측에 게시한다. 프론트엔드는 Kalsae 런타임의
    /// `listen()` API를 통해 수신한다.
    func postMessage(_ message: KSIPCMessage) async throws(KSError)

    /// JS에서 인바운드 IPC 메시지마다 호출되는 핸들러를 설치한다.
    /// WebView당 정확히 하나의 핸들러만 설정할 수 있다.
    func setMessageHandler(
        _ handler: @Sendable @escaping (KSIPCMessage) async -> Void
    ) async

    /// 루트 문서를 제공할 때 스킴 핸들러가 사용할
    /// 콘텐츠 보안 정책을 설정한다.
    func setContentSecurityPolicy(_ csp: String) async throws(KSError)

    /// 플랫폼과 빌드 구성이 허용하는 경우 DevTools를 연다.
    func openDevTools() async throws(KSError)
}
