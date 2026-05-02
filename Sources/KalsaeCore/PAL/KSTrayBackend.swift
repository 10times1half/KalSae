/// 시스템 트레이 / 상태 표시줄 아이템.
import Foundation

public protocol KSTrayBackend: Sendable {
    func install(_ config: KSTrayConfig) async throws(KSError)
    func setTooltip(_ tooltip: String) async throws(KSError)
    func setMenu(_ items: [KSMenuItem]) async throws(KSError)
    func remove() async
}
