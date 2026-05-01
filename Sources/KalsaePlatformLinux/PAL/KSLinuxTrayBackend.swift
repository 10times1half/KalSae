#if os(Linux)
public import KalsaeCore
public import Foundation

/// Linux stub for `KSTrayBackend`.
///
/// A full implementation requires AppIndicator3 / libayatana-appindicator3
/// and a corresponding C shim. Until that shim is wired in, all methods
/// throw `unsupportedPlatform` so callers can detect the capability gap.
public struct KSLinuxTrayBackend: KSTrayBackend, Sendable {
    public init() {}

    public func install(_ config: KSTrayConfig) async throws(KSError) {
        throw KSError(code: .unsupportedPlatform,
                      message: "KSLinuxTrayBackend: system tray requires AppIndicator3 (not yet implemented)")
    }

    public func setTooltip(_ tooltip: String) async throws(KSError) {
        throw KSError(code: .unsupportedPlatform,
                      message: "KSLinuxTrayBackend.setTooltip: not yet implemented")
    }

    public func setMenu(_ items: [KSMenuItem]) async throws(KSError) {
        throw KSError(code: .unsupportedPlatform,
                      message: "KSLinuxTrayBackend.setMenu: not yet implemented")
    }

    public func remove() async {}
}
#endif
