import Foundation

extension KSBuiltinCommands {
    /// `__ks.notification.*` 핸들러를 등록한다 — `requestPermission`,
    /// `post`, `cancel`. 각 작업은 고유한 scope 플래그로 게이팅되며,
    /// 거부된 호출은 `commandNotAllowed`로 실패한다.
    static func registerNotificationCommands(
        into registry: KSCommandRegistry,
        notifications: any KSNotificationBackend,
        scope: KSNotificationScope
    ) async {
        await registerQuery(registry, "__ks.notification.requestPermission") { _ throws(KSError) -> Bool in
            guard scope.requestPermission else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "security.notifications.requestPermission is disabled")
            }
            return await notifications.requestPermission()
        }
        await register(registry, "__ks.notification.post") { (args: KSNotification) throws(KSError) -> Empty in
            guard scope.post else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "security.notifications.post is disabled")
            }
            try await notifications.post(args)
            return Empty()
        }
        await register(registry, "__ks.notification.cancel") { (args: IDArg) throws(KSError) -> Empty in
            guard scope.cancel else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "security.notifications.cancel is disabled")
            }
            await notifications.cancel(id: args.id)
            return Empty()
        }
    }
}
