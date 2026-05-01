public import Foundation

/// 플랫폼별 스킴 핸들러가 `https://app.Kalsae/`(Windows 가상 호스트) 또는
/// `ks://localhost/`(macOS/Linux)와 같은 커스텀 오리진 아래에서
/// 프론트엔드의 정적 파일을 제공하는 데 사용하는 최소 자산 리졸버.
///
/// 리졸버는 순수 값이다; 파일 핸들을 소유하지 않으며 호출자 스레드에서
/// 블로킹 I/O를 수행한다. 스킴 핸들러는 백그라운드 큐에서 이를 호출하고
/// 자체 스레딩 규칙을 통해 웹 엔진에 결과를 전달할 것으로 예상된다.
public struct KSAssetResolver: Sendable {
    /// 절대 루트 디렉터리. 모든 해결 경로는 이 디렉터리 내에 있어야 한다 —
    /// `..`를 통해 이스케이프하는 요청은 `.fsScopeDenied`로 거부된다.
    public let root: URL

    /// 요청 경로가 `""` 또는 `"/"`일 때 제공되는 파일.
    public let indexFileName: String

    /// 자산 바이트를 위한 선택적 인프로세스 LRU 캐시. `nil`이면
    /// 모든 요청이 디스크에서 다시 읽는다 (원래 동작).
    public let cache: KSAssetCache?

    public init(root: URL,
                indexFileName: String = "index.html",
                cache: KSAssetCache? = nil) {
        self.root = root.standardizedFileURL
        self.indexFileName = indexFileName
        self.cache = cache
    }

    /// 리졸버 조회 결과.
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

    /// 리졸버 루트에 대해 `path`를 해석하고 바이트와 추정 MIME 타입을
    /// 반환한다. 파일이 없거나 샌드박스 이스케이프 시 `KSError`를 던진다.
    ///
    /// - `path`는 쿼리/프래그먼트가 없는 URL 경로다. 선행 `/`는 허용된다.
    ///   `""`와 `"/"`는 `indexFileName`에 매핑된다.
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

        // 심링크 해석: 루트 내부의 심링크가 외부를 가리킬 수 있다.
        // 두 번째 방어선으로 실제 경로(모든 심링크가 해석된)를 비교한다.
        let realCandidate = candidate.resolvingSymlinksInPath().path
        let realRoot = root.resolvingSymlinksInPath().path
        if !realCandidate.hasPrefix(realRoot) {
            throw KSError(code: .fsScopeDenied,
                message: "asset path resolves via symlink outside resolver root: \(path)")
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

/// 일반적인 프론트엔드 번들이 내보내는 타입을 다루는 작은 확장자-MIME 매퍼.
/// 알 수 없는 확장자는 `application/octet-stream`을 받는다.
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
