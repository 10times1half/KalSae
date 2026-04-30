#if os(macOS)
internal import AppKit
public import KalsaeCore
public import Foundation

/// macOS implementation of `KSDialogBackend`.
public struct KSMacDialogBackend: KSDialogBackend, Sendable {
    public init() {}

    public func openFile(options: KSOpenFileOptions,
                         parent: KSWindowHandle?) async throws(KSError) -> [URL] {
        let urls: [URL] = await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = options.title ?? "Open"
            panel.allowsMultipleSelection = options.allowsMultiple
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            if let dir = options.defaultDirectory { panel.directoryURL = dir }
            if !options.filters.isEmpty { applyFilters(options.filters, to: panel) }
            let nsParent = resolveParent(parent)
            let response = nsParent != nil ? panel.beginSheetModal(for: nsParent!) : panel.runModal()
            return response == .OK ? panel.urls : []
        }
        return urls
    }

    public func saveFile(options: KSSaveFileOptions,
                         parent: KSWindowHandle?) async throws(KSError) -> URL? {
        await MainActor.run {
            let panel = NSSavePanel()
            panel.title = options.title ?? "Save"
            if let dir = options.defaultDirectory { panel.directoryURL = dir }
            panel.nameFieldStringValue = options.defaultFileName ?? ""
            if !options.filters.isEmpty { applyFilters(options.filters, to: panel) }
            let nsParent = resolveParent(parent)
            let response = nsParent != nil
                ? panel.runModal().rawValue == NSApplication.ModalResponse.OK.rawValue ? NSApplication.ModalResponse.OK : .cancel
                : panel.runModal()
            return response == .OK ? panel.url : nil
        }
    }

    public func selectFolder(options: KSSelectFolderOptions,
                             parent: KSWindowHandle?) async throws(KSError) -> URL? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.title = options.title ?? "Select Folder"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            if let dir = options.defaultDirectory { panel.directoryURL = dir }
            let nsParent = resolveParent(parent)
            let response = nsParent != nil ? panel.beginSheetModal(for: nsParent!) : panel.runModal()
            return response == .OK ? panel.url : nil
        }
    }

    @discardableResult
    public func message(_ options: KSMessageOptions,
                        parent: KSWindowHandle?) async throws(KSError) -> KSMessageResult {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = options.title
            alert.informativeText = options.message
            if let detail = options.detail, !detail.isEmpty {
                alert.informativeText = "\(options.message)\n\n\(detail)"
            }

            switch options.kind {
            case .info:     alert.alertStyle = .informational
            case .warning:  alert.alertStyle = .warning
            case .error:    alert.alertStyle = .critical
            case .question: alert.alertStyle = .informational
            }

            switch options.buttons {
            case .ok:
                alert.addButton(withTitle: "OK")
            case .okCancel:
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")
            case .yesNo:
                alert.addButton(withTitle: "Yes")
                alert.addButton(withTitle: "No")
            case .yesNoCancel:
                alert.addButton(withTitle: "Yes")
                alert.addButton(withTitle: "No")
                alert.addButton(withTitle: "Cancel")
            }

            let nsParent = resolveParent(parent)
            let response = nsParent != nil
                ? alert.beginSheetModal(for: nsParent!)
                : alert.runModal()

            switch response {
            case .alertFirstButtonReturn: return options.buttons == .yesNo ? .yes : .ok
            case .alertSecondButtonReturn:
                switch options.buttons {
                case .okCancel: return .cancel
                case .yesNo, .yesNoCancel: return .no
                default: return .cancel
                }
            case .alertThirdButtonReturn: return .cancel
            default: return .cancel
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func resolveParent(_ handle: KSWindowHandle?) -> NSWindow? {
        guard let h = handle else { return NSApplication.shared.keyWindow }
        return KSMacHandleRegistry.shared.window(for: h)?.nsWindow
    }

    @MainActor
    private func applyFilters(_ filters: [KSFileFilter], to panel: NSSavePanel) {
        var types: [UTType] = []
        for f in filters {
            for ext in f.extensions {
                if let ut = UTType(filenameExtension: ext) { types.append(ut) }
            }
        }
        if !types.isEmpty { panel.allowedContentTypes = types }
    }
}
#endif