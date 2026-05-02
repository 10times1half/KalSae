#if os(Linux)
    internal import CKalsaeGtk
    internal import Glibc
    public import KalsaeCore

    /// Linux implementation of `KSMenuBackend` using GMenuModel +
    /// GtkPopoverMenuBar (window menu) and GtkPopoverMenu (context menu).
    ///
    /// Menu activation is routed through `KSLinuxCommandRouter.shared`, which
    /// mirrors the macOS / Windows pattern wired in `KSApp.swift`.
    public struct KSLinuxMenuBackend: KSMenuBackend, Sendable {
        public init() {}

        /// On Linux there is no system-wide app menu bar. Delegate to the
        /// primary window's menu bar, if one exists.
        public func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) {
            let result: Result<Void, KSError> = await MainActor.run {
                guard let handle = KSLinuxHandleRegistry.shared.allHandles().first,
                    let entry = KSLinuxHandleRegistry.shared.entry(for: handle)
                else {
                    return .success(())  // no window yet — silent no-op
                }
                flatEntries(items) { ptr, count in
                    ks_gtk_host_install_menu(
                        entry.host.hostPtr,
                        ptr, count,
                        linuxMenuTrampoline,
                        nil)
                }
                return .success(())
            }
            switch result {
            case .success: return
            case .failure(let e): throw e
            }
        }

        public func installWindowMenu(
            _ handle: KSWindowHandle,
            items: [KSMenuItem]
        ) async throws(KSError) {
            let result: Result<Void, KSError> = await MainActor.run {
                guard let entry = KSLinuxHandleRegistry.shared.entry(for: handle) else {
                    return .failure(
                        KSError(
                            code: .windowCreationFailed,
                            message: "installWindowMenu: unknown handle"))
                }
                flatEntries(items) { ptr, count in
                    ks_gtk_host_install_menu(
                        entry.host.hostPtr,
                        ptr, count,
                        linuxMenuTrampoline,
                        nil)
                }
                return .success(())
            }
            switch result {
            case .success: return
            case .failure(let e): throw e
            }
        }

        public func showContextMenu(
            _ items: [KSMenuItem],
            at point: KSPoint,
            in handle: KSWindowHandle?
        ) async throws(KSError) {
            let result: Result<Void, KSError> = await MainActor.run {
                let hostPtr: OpaquePointer?
                if let h = handle {
                    guard let entry = KSLinuxHandleRegistry.shared.entry(for: h) else {
                        return .failure(
                            KSError(
                                code: .windowCreationFailed,
                                message: "showContextMenu: unknown handle"))
                    }
                    hostPtr = entry.host.hostPtr
                } else {
                    hostPtr =
                        KSLinuxHandleRegistry.shared
                        .allHandles().first
                        .flatMap { KSLinuxHandleRegistry.shared.entry(for: $0) }?.host.hostPtr
                }
                guard let ptr = hostPtr else {
                    return .failure(
                        KSError(
                            code: .unsupportedPlatform,
                            message: "showContextMenu: no GTK window available"))
                }
                flatEntries(items) { entriesPtr, count in
                    ks_gtk_host_show_context_menu(
                        ptr,
                        entriesPtr, count,
                        Int32(point.x), Int32(point.y),
                        linuxMenuTrampoline,
                        nil)
                }
                return .success(())
            }
            switch result {
            case .success: return
            case .failure(let e): throw e
            }
        }
    }

    // MARK: - Flat-stream encoder

    /// Encodes a `[KSMenuItem]` tree into a flat `[KSMenuEntry]` stream and
    /// calls `body` with a pointer + count valid only for the call duration.
    ///
    /// Stream tokens:
    ///   kind 0  action
    ///   kind 1  separator
    ///   kind 2  submenu_start
    ///   kind 3  submenu_end
    ///   kind 4  section_start  (not used yet — reserved)
    ///   kind 5  section_end
    private func flatEntries(
        _ items: [KSMenuItem],
        body: (UnsafePointer<KSMenuEntry>?, Int32) -> Void
    ) {
        // Collect C strings to free after the call.
        var cstrings: [UnsafeMutablePointer<CChar>?] = []

        func cstr(_ s: String?) -> UnsafePointer<CChar>? {
            guard let s else { return nil }
            let p = strdup(s)
            cstrings.append(p)
            return UnsafePointer(p)
        }

        func flatten(_ list: [KSMenuItem], into out: inout [KSMenuEntry]) {
            for item in list {
                switch item.kind {
                case .separator:
                    out.append(
                        KSMenuEntry(
                            kind: 1,
                            label: nil,
                            action_id: nil,
                            enabled: 1,
                            checked: 0))
                case .submenu:
                    out.append(
                        KSMenuEntry(
                            kind: 2,
                            label: cstr(item.label),
                            action_id: nil,
                            enabled: 1,
                            checked: 0))
                    flatten(item.submenu ?? [], into: &out)
                    out.append(
                        KSMenuEntry(
                            kind: 3,
                            label: nil,
                            action_id: nil,
                            enabled: 1,
                            checked: 0))
                case .action:
                    // Pass the `command` as the action_id so the trampoline
                    // can dispatch it directly. Fall back to `id` if no command.
                    let actionId = item.command ?? item.id
                    out.append(
                        KSMenuEntry(
                            kind: 0,
                            label: cstr(item.label),
                            action_id: cstr(actionId),
                            enabled: item.enabled ? 1 : 0,
                            checked: (item.checked ?? false) ? 1 : 0))
                }
            }
        }

        var entries: [KSMenuEntry] = []
        flatten(items, into: &entries)

        if entries.isEmpty {
            body(nil, 0)
        } else {
            entries.withUnsafeBufferPointer { buf in
                body(buf.baseAddress, Int32(buf.count))
            }
        }
        for p in cstrings { free(p) }
    }

    // MARK: - Activate trampoline

    /// Global `@convention(c)` callback. `action_id` contains the command
    /// string we stored via `KSMenuItem.command`. Dispatches through
    /// `KSLinuxCommandRouter.shared` on the GTK main thread.
    private let linuxMenuTrampoline: KSGtkMenuActivateFn = { actionId, _ in
        guard let actionId else { return }
        let command = String(cString: actionId)
        guard !command.isEmpty else { return }
        MainActor.assumeIsolated {
            KSLinuxCommandRouter.shared.dispatch(command: command, itemID: nil)
        }
    }
#endif
