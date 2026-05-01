#if os(macOS)
internal import AppKit
public import KalsaeCore
public import Foundation

/// NSPasteboard를 사용하는 `KSClipboardBackend`의 macOS 구현체.
public struct KSMacClipboardBackend: KSClipboardBackend, Sendable {
    public init() {}

    public func readText() async throws(KSError) -> String? {
        await MainActor.run {
            NSPasteboard.general.string(forType: .string)
        }
    }

    public func writeText(_ text: String) async throws(KSError) {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    public func readImage() async throws(KSError) -> Data? {
        await MainActor.run {
            NSPasteboard.general.data(forType: .png)
                ?? NSPasteboard.general.data(forType: .tiff).flatMap { tiff in
                    NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                }
        }
    }

    public func writeImage(_ image: Data) async throws(KSError) {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(image, forType: .png)
        }
    }

    public func clear() async throws(KSError) {
        await MainActor.run {
            NSPasteboard.general.clearContents()
        }
    }

    public func hasFormat(_ format: String) async -> Bool {
        await MainActor.run {
            switch format.lowercased() {
            case "text":  return NSPasteboard.general.availableType(from: [.string]) != nil
            case "image": return NSPasteboard.general.availableType(from: [.png, .tiff]) != nil
            case "files": return NSPasteboard.general.availableType(from: [.fileURL]) != nil
            default:      return false
            }
        }
    }
}
#endif