import Foundation

extension KSBuiltinCommands {
    /// `__ks.notification.*` 핸들러를 등록한다 — `requestPermission`,
    /// `post`, `cancel`. 각 작업은 고유한 scope 플래그로 게이팅되며,
    /// 거부된 호출은 `commandNotAllowed`로 실패한다.
    ///
    /// `post` 의 `iconPath` 는 RFC-002 §2.2(취약점 #2-bis)에 따라 `fsScope` 로
    /// 검증한다 — placeholder 확장 후 표준화된 절대 경로가 허용되어야 OS에 전달된다.
    static func registerNotificationCommands(
        into registry: KSCommandRegistry,
        notifications: any KSNotificationBackend,
        scope: KSNotificationScope,
        fsScope: KSFSScope,
        fsCtx: KSFSScope.ExpansionContext
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
            // 검증한 expanded 경로를 PAL에 전달해 TOCTOU 우회를 방지.
            var sanitized = args
            if let raw = args.iconPath {
                let expanded = KSFSScope.expand(raw, in: fsCtx)
                let url = URL(fileURLWithPath: expanded).standardizedFileURL
                guard fsScope.permits(absolutePath: url.path, in: fsCtx) else {
                    throw KSError(
                        code: .fsScopeDenied,
                        message: "security.fs denies notification iconPath",
                        data: .string(url.path))
                }
                sanitized.iconPath = url.path
            }
            try await notifications.post(sanitized)
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
