#if os(iOS)
    internal import UIKit
    public import KalsaeCore
    public import Foundation

    public struct KSiOSShellBackend: KSShellBackend, Sendable {
        public init() {}

        public func openExternal(_ url: URL) async throws(KSError) {
            let opened = await MainActor.run {
                UIApplication.shared.canOpenURL(url)
            }
            if !opened {
                throw KSError(
                    code: .shellInvocationFailed,
                    message: "Cannot open URL on iOS: \(url.absoluteString)")
            }

            await MainActor.run {
                UIApplication.shared.open(url)
            }
        }

        public func showItemInFolder(_ url: URL) async throws(KSError) {
            try await openExternal(url)
        }

        public func moveToTrash(_ url: URL) async throws(KSError) {
            _ = url
            throw KSError.unsupportedPlatform("moveToTrash is not supported on iOS sandbox")
        }
    }
#endif
