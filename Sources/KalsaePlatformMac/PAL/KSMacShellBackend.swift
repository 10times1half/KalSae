#if os(macOS)
internal import AppKit
public import KalsaeCore
public import Foundation

/// macOS implementation of `KSShellBackend`.
public struct KSMacShellBackend: KSShellBackend, Sendable {
    public init() {}

    public func openExternal(_ url: URL) async throws(KSError) {
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

    public func showItemInFolder(_ url: URL) async throws(KSError) {
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    public func moveToTrash(_ url: URL) async throws(KSError) {
        try await MainActor.run {
            let fm = FileManager.default
            var resultingURL: NSURL?
            try fm.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }
}
#endif