import Foundation

extension KSBuiltinCommands {
    /// `__ks.shell.*` 핸들러를 등록한다 — `openExternal`,
    /// `showItemInFolder`, `moveToTrash`. 모두 `scope`로 게이팅되며,
    /// 거부된 요청은 `commandNotAllowed`로 실패한다.
    ///
    /// `showItemInFolder` / `moveToTrash` 는 추가로 `scope.fsScope` 에 대해
    /// 대상 경로(placeholder 확장 → 표준화된 절대 경로)를 검증한다.
    /// RFC-002 §2.1 — boolean 플래그만 검사하던 이전 동작은 시스템 경로 노출을 허용했다.
    static func registerShellCommands(
        into registry: KSCommandRegistry,
        shell: any KSShellBackend,
        scope: KSShellScope,
        fsCtx: KSFSScope.ExpansionContext
    ) async {
        // 검증한 절대 경로를 PAL에 그대로 전달해 TOCTOU 우회를 방지한다.
        @Sendable
        func validatedURL(_ raw: String) throws(KSError) -> URL {
            let expanded = KSFSScope.expand(raw, in: fsCtx)
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            guard scope.fsScope.permits(absolutePath: url.path, in: fsCtx) else {
                throw KSError(
                    code: .fsScopeDenied,
                    message:
                        "security.shell.fsScope denies path",
                    data: .string(url.path))
            }
            return url
        }

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
            let u = try validatedURL(args.url)
            try await shell.showItemInFolder(u)
            return Empty()
        }
        await register(registry, "__ks.shell.moveToTrash") { (args: URLArg) throws(KSError) -> Empty in
            guard scope.moveToTrash else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "security.shell.moveToTrash is disabled")
            }
            let u = try validatedURL(args.url)
            try await shell.moveToTrash(u)
            return Empty()
        }
    }
}
