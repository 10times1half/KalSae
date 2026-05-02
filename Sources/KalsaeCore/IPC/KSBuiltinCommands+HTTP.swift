import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
extension KSBuiltinCommands {
    // MARK: - HTTP arg / result types

    /// Tauri 호환 `__ks.http.fetch` 인자 형태.
    struct HTTPFetchArg: Codable, Sendable {
        let url: String
        let method: String?
        let headers: [String: String]?
        /// UTF-8 문자열 바디(`bodyText`) 또는 base64 인코딩된 페이로드
        /// (`bodyBytes`) 중 하나. 둘 다 설정된 경우 `bodyBytes`가 우선한다.
        let bodyText: String?
        let bodyBytes: String?
        /// 타임아웃(초 단위). 0/nil → URLSession 기본값(60초).
        let timeoutSeconds: Double?
        /// `"text"`(기본값), `"binary"`, `"json"` 중 하나. JS로 응답 페이로드를
        /// 인코딩하는 방식을 결정한다.
        let responseType: String?
    }

    struct HTTPFetchResult: Codable, Sendable {
        let status: Int
        let statusText: String
        let headers: [String: String]
        /// `responseType`에 따라 인코딩된다:
        ///   * `"text"`   — UTF-8 문자열 (응답이 바이너리일 경우 손실 가능).
        ///   * `"binary"` — base64 인코딩 바이트.
        ///   * `"json"`   — UTF-8 문자열 (호출자가 파싱).
        let body: String
        let url: String
    }

    /// `__ks.http.*` 명령을 등록한다. 단일 `fetch` 명령은 Tauri 호환
    /// 네트워크 기본 요소로, 모든 호출은 `URLSession.shared`를 통해
    /// `scope`에 의해 게이팅된다.
    ///
    /// `scope`는 **기본 거부** 방식이다(빈 `allow` 목록은 모든 URL을 거부).
    /// 호스트 앱은 신뢰할 오리진 또는 URL 프리픽스를 추가해야 한다.
    /// 메서드 게이팅은 `scope.permits(method:)`를 사용하고, `scope.defaultHeaders`에
    /// 선언된 기본 헤더는 모든 요청에 병합된다(호출자 헤더가 우선).
    static func registerHTTPCommands(
        into registry: KSCommandRegistry,
        scope: KSHTTPScope,
        session: URLSession = .shared
    ) async {
        await register(registry, "__ks.http.fetch") { (args: HTTPFetchArg) throws(KSError) -> HTTPFetchResult in
            // 1. URL/메서드 게이트.
            guard scope.permits(urlString: args.url) else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "security.http denies URL '\(args.url)'",
                    data: .string(args.url))
            }
            guard let url = URL(string: args.url) else {
                throw KSError(
                    code: .invalidArgument,
                    message: "Invalid URL: \(args.url)")
            }
            let method = (args.method ?? "GET").uppercased()
            guard scope.permits(method: method) else {
                throw KSError(
                    code: .commandNotAllowed,
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
                    throw KSError(
                        code: .invalidArgument,
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
                throw KSError(
                    code: .ioFailed,
                    message: "http.fetch failed: \(error.localizedDescription)")
            }
            guard let http = response as? HTTPURLResponse else {
                throw KSError(
                    code: .ioFailed,
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
                throw KSError(
                    code: .invalidArgument,
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
