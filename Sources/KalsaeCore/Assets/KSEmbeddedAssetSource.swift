public import Foundation

/// 메모리에 이미 올라온 자산 딕셔너리를 서빙하는 간단한 백엔드.
///
/// Phase 2에서는 zip/blob 기반 구현이 이 타입 또는 동일 프로토콜을 따르는
/// 별도 구현으로 확장된다. 현재는 테스트/임베드 실험용 토대 역할을 한다.
public struct KSEmbeddedAssetSource: KSAssetSource, Sendable {
    public let assets: [String: Data]

    public init(assets: [String: Data]) {
        self.assets = assets
    }

    public func load(relativePath: String, indexFileName: String) throws(KSError) -> Data {
        let rel = relativePath.isEmpty ? indexFileName : relativePath
        if let data = assets[rel] {
            return data
        }
        throw KSError(
            code: .ioFailed,
            message: "embedded asset not found: \(rel)")
    }
}
