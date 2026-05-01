#if os(iOS)
internal import UIKit
public import KalsaeCore
public import Foundation

@MainActor
internal final class KSiOSHandleRegistry {
    static let shared = KSiOSHandleRegistry()

    private var byLabel: [String: KSWindowHandle] = [:]
    private var webViewByLabel: [String: KSiOSWebViewHost] = [:]

    func register(label: String) -> KSWindowHandle {
        let raw = UInt64.random(in: 1...UInt64.max)
        let handle = KSWindowHandle(label: label, rawValue: raw)
        byLabel[label] = handle
        return handle
    }

    func registerWebView(_ host: KSiOSWebViewHost, for label: String) {
        webViewByLabel[label] = host
    }

    func unregister(_ handle: KSWindowHandle) {
        byLabel.removeValue(forKey: handle.label)
        webViewByLabel.removeValue(forKey: handle.label)
    }

    func handle(for label: String) -> KSWindowHandle? {
        byLabel[label]
    }

    func webView(for label: String) -> KSiOSWebViewHost? {
        webViewByLabel[label]
    }

    func all() -> [KSWindowHandle] {
        Array(byLabel.values)
    }
}

public struct KSiOSWindowBackend: KSWindowBackend, Sendable {
    public init() {}

    public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
        await MainActor.run {
            KSiOSHandleRegistry.shared.register(label: config.label)
        }
    }

    public func close(_ handle: KSWindowHandle) async throws(KSError) {
        await MainActor.run {
            KSiOSHandleRegistry.shared.unregister(handle)
        }
    }

    public func show(_ handle: KSWindowHandle) async throws(KSError) {
        try await ensureHandleExists(handle)
    }

    public func hide(_ handle: KSWindowHandle) async throws(KSError) {
        try await ensureHandleExists(handle)
    }

    public func focus(_ handle: KSWindowHandle) async throws(KSError) {
        try await ensureHandleExists(handle)
    }

    public func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {
        _ = title
        try await ensureHandleExists(handle)
    }

    public func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
        _ = (width, height)
        try await ensureHandleExists(handle)
    }

    public func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend {
        let host = await MainActor.run {
            KSiOSHandleRegistry.shared.webView(for: handle.label)
        }
        guard let host else {
            throw KSError(code: .webviewInitFailed,
                          message: "WebView not initialised for window '\(handle.label)'")
        }
        return host
    }

    public func all() async -> [KSWindowHandle] {
        await MainActor.run {
            KSiOSHandleRegistry.shared.all()
        }
    }

    public func find(label: String) async -> KSWindowHandle? {
        await MainActor.run {
            KSiOSHandleRegistry.shared.handle(for: label)
        }
    }

    private func ensureHandleExists(_ handle: KSWindowHandle) async throws(KSError) {
        let exists = await MainActor.run {
            KSiOSHandleRegistry.shared.handle(for: handle.label) != nil
        }
        if !exists {
            throw KSError(code: .windowCreationFailed,
                          message: "No iOS window registered for label '\(handle.label)'")
        }
    }
}
#endif
