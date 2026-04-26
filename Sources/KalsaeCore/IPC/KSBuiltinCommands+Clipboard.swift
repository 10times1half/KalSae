import Foundation

extension KSBuiltinCommands {
    /// Registers `__ks.clipboard.*` handlers — `readText`, `writeText`,
    /// `clear`, `hasFormat`. (Image read/write is not yet wired through
    /// JSON IPC; it's available via the Swift API only.)
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
