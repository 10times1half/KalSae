#if os(macOS)
internal import ServiceManagement
public import KalsaeCore
public import Foundation

/// SMAppService (macOS 13+)를 사용하는 `KSAutostartBackend`의 macOS 구현체.
public struct KSMacAutostartBackend: KSAutostartBackend, Sendable {
    public init() {}

    public func enable() throws(KSError) {
        guard #available(macOS 13.0, *) else {
            throw KSError(code: .unsupportedPlatform,
                          message: "Autostart requires macOS 13+")
        }
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw KSError(code: .platformInitFailed,
                          message: "SMAppService.register failed: \(error)")
        }
    }

    public func disable() throws(KSError) {
        guard #available(macOS 13.0, *) else {
            throw KSError(code: .unsupportedPlatform,
                          message: "Autostart requires macOS 13+")
        }
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            throw KSError(code: .platformInitFailed,
                          message: "SMAppService.unregister failed: \(error)")
        }
    }

    public func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}
#endif