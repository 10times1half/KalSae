import Foundation

extension KSBuiltinCommands {
    /// Registers `__ks.notification.*` handlers — `requestPermission`,
    /// `post`, `cancel`. Each operation is gated by its own scope flag;
    /// denied calls fail with `commandNotAllowed`.
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
