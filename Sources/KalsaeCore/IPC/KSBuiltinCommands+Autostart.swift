import Foundation

extension KSBuiltinCommands {
    struct AutostartIsEnabledResult: Codable, Sendable {
        let enabled: Bool
    }

    /// `__ks.autostart.enable`, `__ks.autostart.disable`,
    /// `__ks.autostart.isEnabled`를 등록한다. 각 명령은 `backend`에 위임된다.
    /// 구현이 없는 플랫폼에서는 호스트가 `nil`을 전달하면 해당 명령이
    /// 설치되지 않는다(호출자는 `commandNotRegistered`를 받으며,
    /// JS 브리지가 이를 거부(rejection)로 매핑한다).
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
