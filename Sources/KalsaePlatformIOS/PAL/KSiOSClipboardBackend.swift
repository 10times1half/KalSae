#if os(iOS)
    internal import UIKit
    public import KalsaeCore
    public import Foundation

    public struct KSiOSClipboardBackend: KSClipboardBackend, Sendable {
        public init() {}

        public func readText() async throws(KSError) -> String? {
            await MainActor.run {
                UIPasteboard.general.string
            }
        }

        public func writeText(_ text: String) async throws(KSError) {
            await MainActor.run {
                UIPasteboard.general.string = text
            }
        }

        public func readImage() async throws(KSError) -> Data? {
            await MainActor.run {
                guard let image = UIPasteboard.general.image else { return nil }
                return image.pngData()
            }
        }

        public func writeImage(_ image: Data) async throws(KSError) {
            await MainActor.run {
                guard let uiImage = UIImage(data: image) else { return }
                UIPasteboard.general.image = uiImage
            }
        }

        public func clear() async throws(KSError) {
            await MainActor.run {
                UIPasteboard.general.items = []
            }
        }

        public func hasFormat(_ format: String) async -> Bool {
            await MainActor.run {
                switch format.lowercased() {
                case "text":
                    return UIPasteboard.general.hasStrings
                case "image", "image/png":
                    return UIPasteboard.general.hasImages
                default:
                    return false
                }
            }
        }
    }
#endif
