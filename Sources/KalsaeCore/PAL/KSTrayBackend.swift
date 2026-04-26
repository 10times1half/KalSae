import Foundation

/// System tray / status item.
public protocol KSTrayBackend: Sendable {
    func install(_ config: KSTrayConfig) async throws(KSError)
    func setTooltip(_ tooltip: String) async throws(KSError)
    func setMenu(_ items: [KSMenuItem]) async throws(KSError)
    func remove() async
}
