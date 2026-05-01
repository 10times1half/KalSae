public import Foundation

/// 임베디드 프론트엔드 리소스에서 `ks://localhost/...` 요청을 처리한다.
///
/// 각 플랫폼은 이를 네이티브 스킴 API로 래핑한다:
/// - macOS: `WKURLSchemeHandler`
/// - Windows: `ICoreWebView2_22::AddWebResourceRequestedFilter`
/// - Linux: `WebKitURISchemeRequest`
public protocol KSSchemeHandler: Sendable {
    /// 이 핸들러가 처리하는 스킴. v0.1에서는 항상 `"ks"`이다.
    var scheme: String { get }

    /// 요청을 처리한다. 구현은 호출하는 플랫폼 스레드를 절대 블록해서는
    /// 안 되며, async 응답을 반환한다.
    func respond(to request: KSSchemeRequest) async -> KSSchemeResponse
}

public struct KSSchemeRequest: Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(url: URL,
                method: String = "GET",
                headers: [String: String] = [:],
                body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct KSSchemeResponse: Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(statusCode: Int = 200,
                headers: [String: String] = [:],
                body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public static func notFound(path: String) -> KSSchemeResponse {
        KSSchemeResponse(
            statusCode: 404,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data("Not Found: \(path)".utf8))
    }
}
