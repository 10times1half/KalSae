import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension KSBuiltinCommands {
    // MARK: - HTTP arg / result types

    /// Tauri-compatible `__ks.http.fetch` argument shape.
    struct HTTPFetchArg: Codable, Sendable {
        let url: String
        let method: String?
        let headers: [String: String]?
        /// Either a UTF-8 string body (`bodyText`) or a base64-encoded
        /// payload (`bodyBytes`). `bodyBytes` wins if both are set.
        let bodyText: String?
        let bodyBytes: String?
        /// Timeout in seconds. 0/nil → URLSession default (60s).
        let timeoutSeconds: Double?
        /// `"text"` (default), `"binary"` or `"json"`. Determines how
        /// the response payload is encoded back to JS.
        let responseType: String?
    }

    struct HTTPFetchResult: Codable, Sendable {
        let status: Int
        let statusText: String
        let headers: [String: String]
        /// Encoded according to `responseType`:
        ///   * `"text"`   — UTF-8 string (lossy if response was binary).
        ///   * `"binary"` — base64-encoded bytes.
        ///   * `"json"`   — UTF-8 string (caller parses).
        let body: String
        let url: String
    }

    /// Registers the `__ks.http.*` commands. The single `fetch` command
    /// is the Tauri-compatible network primitive: every call goes
    /// through `URLSession.shared` and is gated by `scope`.
    ///
    /// `scope` is **deny-by-default** (empty `allow` list rejects every
    /// URL). The host app must add origins or URL prefixes it trusts.
    /// Method gating uses `scope.permits(method:)`; default headers
    /// declared in `scope.defaultHeaders` are merged into every request
    /// (caller-supplied headers override).
    static func registerHTTPCommands(
        into registry: KSCommandRegistry,
        scope: KSHTTPScope,
        session: URLSession = .shared
    ) async {
        await register(registry, "__ks.http.fetch") { (args: HTTPFetchArg) throws(KSError) -> HTTPFetchResult in
            // 1. URL/메서드 게이트.
            guard scope.permits(urlString: args.url) else {
                throw KSError(code: .commandNotAllowed,
                    message: "security.http denies URL '\(args.url)'",
                    data: .string(args.url))
            }
            guard let url = URL(string: args.url) else {
                throw KSError(code: .invalidArgument,
                    message: "Invalid URL: \(args.url)")
            }
            let method = (args.method ?? "GET").uppercased()
            guard scope.permits(method: method) else {
                throw KSError(code: .commandNotAllowed,
                    message: "security.http denies method '\(method)'",
                    data: .string(method))
            }

            // 2. URLRequest 구성.
            var req = URLRequest(url: url)
            req.httpMethod = method
            if let t = args.timeoutSeconds, t > 0 {
                req.timeoutInterval = t
            }
            // 기본 헤더 → 호출자 헤더 순으로 병합(호출자가 우선).
            for (k, v) in scope.defaultHeaders {
                req.setValue(v, forHTTPHeaderField: k)
            }
            for (k, v) in args.headers ?? [:] {
                req.setValue(v, forHTTPHeaderField: k)
            }
            if let bytes = args.bodyBytes {
                guard let data = Data(base64Encoded: bytes) else {
                    throw KSError(code: .invalidArgument,
                        message: "http.fetch: bodyBytes is not valid base64")
                }
                req.httpBody = data
            } else if let text = args.bodyText {
                req.httpBody = Data(text.utf8)
            }

            // 3. 비동기 전송.
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: req)
            } catch {
                throw KSError(code: .ioFailed,
                    message: "http.fetch failed: \(error.localizedDescription)")
            }
            guard let http = response as? HTTPURLResponse else {
                throw KSError(code: .ioFailed,
                    message: "http.fetch: response is not HTTP")
            }

            // 4. 헤더는 String:String로 직렬화.
            var hs: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    hs[k] = v
                }
            }

            // 5. 응답 타입에 따른 인코딩.
            let responseType = (args.responseType ?? "text").lowercased()
            let body: String
            switch responseType {
            case "binary":
                body = data.base64EncodedString()
            case "json", "text":
                body = String(data: data, encoding: .utf8) ?? ""
            default:
                throw KSError(code: .invalidArgument,
                    message: "http.fetch: unknown responseType '\(responseType)'")
            }

            return HTTPFetchResult(
                status: http.statusCode,
                statusText: HTTPURLResponse.localizedString(
                    forStatusCode: http.statusCode),
                headers: hs,
                body: body,
                url: http.url?.absoluteString ?? args.url)
        }
    }
}
