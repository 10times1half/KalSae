public import Foundation

/// Serves `ks://localhost/...` requests from embedded frontend resources.
///
/// Each platform wraps this in its native scheme API:
/// - macOS: `WKURLSchemeHandler`
/// - Windows: `ICoreWebView2_22::AddWebResourceRequestedFilter`
/// - Linux: `WebKitURISchemeRequest`
public protocol KSSchemeHandler: Sendable {
    /// Scheme served by this handler. Always `"ks"` for v0.1.
    var scheme: String { get }

    /// Resolves a request. Implementations must never block the calling
    /// platform thread; they return an async response.
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
