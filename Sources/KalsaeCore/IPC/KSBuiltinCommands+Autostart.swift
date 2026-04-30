import Foundation

extension KSBuiltinCommands {
    struct AutostartIsEnabledResult: Codable, Sendable {
        let enabled: Bool
    }

    /// Registers `__ks.autostart.enable`, `__ks.autostart.disable`, and
    /// `__ks.autostart.isEnabled`. Each command delegates to `backend`.
    /// On platforms without an implementation, the host should pass
    /// `nil` and the commands will not be installed (callers receive
    /// `commandNotRegistered`, which the JS bridge maps to a rejection).
    static func registerAutostartCommands(
        into registry: KSCommandRegistry,
        backend: any KSAutostartBackend
    ) async {
        await register(registry, "__ks.autostart.enable") { (_: Empty) throws(KSError) -> Empty in
            try backend.enable()
            return Empty()
        }
        await register(registry, "__ks.autostart.disable") { (_: Empty) throws(KSError) -> Empty in
            try backend.disable()
            return Empty()
        }
        await registerQuery(registry, "__ks.autostart.isEnabled") { (_: Empty) throws(KSError) -> AutostartIsEnabledResult in
            AutostartIsEnabledResult(enabled: backend.isEnabled())
        }
    }
}
