import Foundation

extension KSBuiltinCommands {
    /// `__ks.shell.*` 핸들러를 등록한다 — `openExternal`,
    /// `showItemInFolder`, `moveToTrash`. 모두 `scope`로 게이팅되며,
    /// 거부된 요청은 `commandNotAllowed`로 실패한다.
    static func registerShellCommands(
        into registry: KSCommandRegistry,
        shell: any KSShellBackend,
        scope: KSShellScope
    ) async {
        await register(registry, "__ks.shell.openExternal") { (args: URLArg) throws(KSError) -> Empty in
            guard let u = URL(string: args.url) else {
                throw KSError(code: .ioFailed, message: "Invalid URL: \(args.url)")
            }
            let scheme = u.scheme ?? ""
            guard scope.permitsScheme(scheme) else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "security.shell.openExternalSchemes denies scheme '\(scheme)'",
                    data: .string(scheme))
            }
            try await shell.openExternal(u)
            return Empty()
        }
        await register(registry, "__ks.shell.showItemInFolder") { (args: URLArg) throws(KSError) -> Empty in
            guard scope.showItemInFolder else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "security.shell.showItemInFolder is disabled")
            }
            let u = URL(fileURLWithPath: args.url)
            try await shell.showItemInFolder(u)
            return Empty()
        }
        await register(registry, "__ks.shell.moveToTrash") { (args: URLArg) throws(KSError) -> Empty in
            guard scope.moveToTrash else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "security.shell.moveToTrash is disabled")
            }
            let u = URL(fileURLWithPath: args.url)
            try await shell.moveToTrash(u)
            return Empty()
        }
    }
}
