#if os(iOS)
    internal import UIKit
    public import KalsaeCore
    public import Foundation

    public struct KSiOSShellBackend: KSShellBackend, Sendable {
        public init() {}

        public func openExternal(_ url: URL) async throws(KSError) {
            // `canOpenURL`은 LSApplicationQueriesSchemes 화이트리스트가 필요하고
            // false-negative가 흔하므로 사전 체크 대신 `open(_:options:completionHandler:)`
            // 결과로 직접 판정한다.
            let opened: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                Task { @MainActor in
                    UIApplication.shared.open(url, options: [:]) { ok in
                        cont.resume(returning: ok)
                    }
                }
            }
            if !opened {
                throw KSError(
                    code: .shellInvocationFailed,
                    message: "Cannot open URL on iOS: \(url.absoluteString)")
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
