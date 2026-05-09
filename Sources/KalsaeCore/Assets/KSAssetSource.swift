public import Foundation

/// `KSAssetResolver`가 실제 바이트를 가져오는 백엔드 추상화.
///
/// - 디스크 기반: `KSDiskAssetSource`
/// - 임베드/메모리 기반: `KSEmbeddedAssetSource`
public protocol KSAssetSource: Sendable {
    /// 정규화된 상대 경로(`index.html`, `assets/app.js` 등)에 대한 바이트를 반환한다.
    /// `relativePath`는 `KSAssetResolver`가 `..` 및 선행 `/`를 제거/검증한 값이다.
    func load(relativePath: String, indexFileName: String) throws(KSError) -> Data
}

/// 디스크 디렉터리에서 자산을 읽는 기본 구현.
public struct KSDiskAssetSource: KSAssetSource, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public func load(relativePath: String, indexFileName: String) throws(KSError) -> Data {
        let rel = relativePath.isEmpty ? indexFileName : relativePath

        if rel.contains("..") || rel.hasPrefix("/") {
            throw KSError(
                code: .fsScopeDenied,
                message: "asset path escapes resolver root: \(relativePath)")
        }

        let candidate =
            root
            .appendingPathComponent(rel)
            .standardizedFileURL

        let rootPath = root.path
        let candidatePath = candidate.path
        if !candidatePath.hasPrefix(rootPath) {
            throw KSError(
                code: .fsScopeDenied,
                message: "asset path escapes resolver root: \(relativePath)")
        }

        let realCandidate = candidate.resolvingSymlinksInPath().path
        let realRoot = root.resolvingSymlinksInPath().path
        if !realCandidate.hasPrefix(realRoot) {
            throw KSError(
                code: .fsScopeDenied,
                message: "asset path resolves via symlink outside resolver root: \(relativePath)")
        }

        do {
            return try Data(contentsOf: candidate)
        } catch {
            throw KSError(
                code: .ioFailed,
                message: "asset not found: \(rel) (\(String(describing: error)))")
        }
    }
}
