import Foundation

extension KSBuiltinCommands {
    /// Registers `__ks.shell.*` handlers — `openExternal`,
    /// `showItemInFolder`, `moveToTrash`. All gated by `scope`; denied
    /// requests fail with `commandNotAllowed`.
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
