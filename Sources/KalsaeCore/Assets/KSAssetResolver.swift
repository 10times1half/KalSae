public import Foundation

/// Minimal asset resolver used by platform-specific scheme handlers to
/// serve the frontend's static files under a custom origin such as
/// `https://app.Kalsae/` (Windows virtual host) or
/// `ks://localhost/` (macOS/Linux).
///
/// The resolver is a pure value; it owns no file handles and performs
/// blocking I/O on the caller's thread. Scheme handlers are expected to
/// invoke it from a background queue and deliver the result to the
/// web engine via its own threading conventions.
public struct KSAssetResolver: Sendable {
    /// Absolute root directory. Every resolved path must stay inside
    /// this directory — requests that escape via `..` are rejected with
    /// `.fsScopeDenied`.
    public let root: URL

    /// File served when the request path is `""` or `"/"`.
    public let indexFileName: String

    /// Optional in-process LRU cache for asset bytes. When `nil`,
    /// every request re-reads from disk (the original behaviour).
    public let cache: KSAssetCache?

    public init(root: URL,
                indexFileName: String = "index.html",
                cache: KSAssetCache? = nil) {
        self.root = root.standardizedFileURL
        self.indexFileName = indexFileName
        self.cache = cache
    }

    /// Result of a resolver lookup.
    public struct Asset: Sendable {
        public let data: Data
        public let mimeType: String
        public let path: String   // 해석된 상대 경로 (로깅용)

        public init(data: Data, mimeType: String, path: String) {
            self.data = data
            self.mimeType = mimeType
            self.path = path
        }
    }

    /// Resolve `path` against the resolver root and return the bytes
    /// plus a best-guess MIME type. Throws `KSError` for missing files
    /// or sandbox escapes.
    ///
    /// - `path` is a URL path without query/fragment. A leading `/` is
    ///   tolerated. `""` and `"/"` map to `indexFileName`.
    public func resolve(path: String) throws(KSError) -> Asset {
        var rel = path
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { rel = indexFileName }

        // 절대 경로와 링크 디렉터리 구성 요소는 파일 시스템에
        // 접근하기 전에 거부한다. `URL` 정규화 또한 2차 방어선으로
        // 사용한다.
        if rel.contains("..") || rel.hasPrefix("/") {
            throw KSError(code: .fsScopeDenied,
                message: "asset path escapes resolver root: \(path)")
        }

        let candidate = root
            .appendingPathComponent(rel)
            .standardizedFileURL

        // 정규화된 URL이 여전히 `root` 내부에 있는지 확인한다.
        let rootPath = root.path
        let candidatePath = candidate.path
        if !candidatePath.hasPrefix(rootPath) {
            throw KSError(code: .fsScopeDenied,
                message: "asset path escapes resolver root: \(path)")
        }

        // 캐시 조회는 정규화된 절대 경로로. 동일 파일에 대한 여러
        // 표기(예: `/x` vs `x`)가 동일 슬롯을 공유하도록 보장.
        if let cache, let cached = cache.lookup(candidatePath) {
            return cached
        }

        let data: Data
        do {
            data = try Data(contentsOf: candidate)
        } catch {
            throw KSError(code: .ioFailed,
                message: "asset not found: \(rel) (\(String(describing: error)))")
        }

        let asset = Asset(
            data: data,
            mimeType: KSContentType.forExtension(candidate.pathExtension),
            path: rel)
        cache?.store(candidatePath, asset)
        return asset
    }
}

/// Tiny extension-to-MIME mapper covering the types a typical frontend
/// bundle emits. Unknown extensions get `application/octet-stream`.
public enum KSContentType {
    public static func forExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm":  return "text/html; charset=utf-8"
        case "js", "mjs":    return "application/javascript; charset=utf-8"
        case "css":          return "text/css; charset=utf-8"
        case "json":         return "application/json; charset=utf-8"
        case "map":          return "application/json; charset=utf-8"
        case "svg":          return "image/svg+xml"
        case "png":          return "image/png"
        case "jpg", "jpeg":  return "image/jpeg"
        case "gif":          return "image/gif"
        case "webp":         return "image/webp"
        case "ico":          return "image/x-icon"
        case "woff":         return "font/woff"
        case "woff2":        return "font/woff2"
        case "ttf":          return "font/ttf"
        case "otf":          return "font/otf"
        case "wasm":         return "application/wasm"
        case "txt":          return "text/plain; charset=utf-8"
        default:             return "application/octet-stream"
        }
    }
}
