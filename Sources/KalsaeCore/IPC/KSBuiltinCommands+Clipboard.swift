import Foundation

extension KSBuiltinCommands {
    /// `__ks.clipboard.*` 핸들러를 등록한다 — `readText`, `writeText`,
    /// `clear`, `hasFormat`. (이미지 읽기/쓰기는 아직 JSON IPC에 연결되지
    /// 않았으며, Swift API를 통해서만 사용 가능하다.)
    static func registerClipboardCommands(
        into registry: KSCommandRegistry,
        clipboard: any KSClipboardBackend
    ) async {
        await registerQuery(registry, "__ks.clipboard.readText") { _ throws(KSError) -> String? in
            try await clipboard.readText()
        }
        await register(registry, "__ks.clipboard.writeText") { (args: TextArg) throws(KSError) -> Empty in
            try await clipboard.writeText(args.text)
            return Empty()
        }
        await register(registry, "__ks.clipboard.clear") { _ throws(KSError) -> Empty in
            try await clipboard.clear()
            return Empty()
        }
        await registerQuery(registry, "__ks.clipboard.hasFormat") { (args: FormatArg) throws(KSError) -> Bool in
            await clipboard.hasFormat(args.format)
        }
    }
}
