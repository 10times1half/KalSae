#if os(iOS)
    internal import UIKit
    public import KalsaeCore
    public import Foundation

    /// 라벨로 등록된 윈도우 핸들과 (있으면) 실제 `UIWindow` /
    /// `KSiOSWebViewHost`를 추적하는 main-actor 보호 레지스트리.
    ///
    /// iOS에서는 `KSiOSDemoHost`가 부팅 흐름에서 메인 윈도우를 등록하고,
    /// `KSiOSAppDelegate.didFinishLaunching` 시점에 실제 `UIWindow`을 연결한다.
    /// `KSiOSWindowBackend`는 등록된 `UIWindow`이 있으면 그 위에서
    /// show/hide/focus/setTitle 동작을 수행한다.
    @MainActor
    internal final class KSiOSHandleRegistry {
        static let shared = KSiOSHandleRegistry()

        private var byLabel: [String: KSWindowHandle] = [:]
        private var webViewByLabel: [String: KSiOSWebViewHost] = [:]
        private var windowByLabel: [String: UIWindow] = [:]

        func register(label: String) -> KSWindowHandle {
            let raw = UInt64.random(in: 1...UInt64.max)
            let handle = KSWindowHandle(label: label, rawValue: raw)
            byLabel[label] = handle
            return handle
        }

        func registerWebView(_ host: KSiOSWebViewHost, for label: String) {
            webViewByLabel[label] = host
        }

        /// `KSiOSAppDelegate`가 호출한다. 메인 윈도우의 `UIWindow`을
        /// 핸들 레이블에 연결해 백엔드에서 show/hide/focus 등을 수행할 수 있게 한다.
        func registerWindow(_ window: UIWindow, for label: String) {
            windowByLabel[label] = window
        }

        func unregister(_ handle: KSWindowHandle) {
            byLabel.removeValue(forKey: handle.label)
            webViewByLabel.removeValue(forKey: handle.label)
            windowByLabel.removeValue(forKey: handle.label)
        }

        func handle(for label: String) -> KSWindowHandle? {
            byLabel[label]
        }

        func webView(for label: String) -> KSiOSWebViewHost? {
            webViewByLabel[label]
        }

        func window(for label: String) -> UIWindow? {
            windowByLabel[label]
        }

        func all() -> [KSWindowHandle] {
            Array(byLabel.values)
        }
    }

    public struct KSiOSWindowBackend: KSWindowBackend, Sendable {
        public init() {}

        /// iOS는 데스크톱식 멀티 윈도우 모델이 없다 — 메인 윈도우는
        /// `KSiOSDemoHost`가 부팅 흐름에서 등록하고 `KSiOSAppDelegate`가
        /// 실제 `UIWindow`을 연결한다. 사용자가 명시적으로 호출하는 `create()`는
        /// **논리적 핸들만** 등록한다. 실제 추가 `UIWindow`은 멀티 씬을 지원하기
        /// 전까지는 생성되지 않으며, 이후 `show/focus/setTitle` 등은 등록된
        /// `UIWindow`이 있을 때만 동작한다.
        public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
            await MainActor.run {
                if let existing = KSiOSHandleRegistry.shared.handle(for: config.label) {
                    return existing
                }
                return KSiOSHandleRegistry.shared.register(label: config.label)
            }
        }

        public func close(_ handle: KSWindowHandle) async throws(KSError) {
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.isHidden = true
                }
                KSiOSHandleRegistry.shared.unregister(handle)
                KSWindowEmitHub.shared.unregister(label: handle.label)
            }
        }

        public func show(_ handle: KSWindowHandle) async throws(KSError) {
            try await ensureHandleExists(handle)
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.makeKeyAndVisible()
                }
            }
        }

        public func hide(_ handle: KSWindowHandle) async throws(KSError) {
            try await ensureHandleExists(handle)
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.isHidden = true
                }
            }
        }

        public func focus(_ handle: KSWindowHandle) async throws(KSError) {
            try await ensureHandleExists(handle)
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.makeKey()
                }
            }
        }

        public func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {
            try await ensureHandleExists(handle)
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.windowScene?.title = title
                }
            }
        }

        /// iOS는 사용자가 윈도우 크기를 프로그래매틱하게 변경하는 개념이 없다
        /// (UIKit이 화면/씬 크기를 통제). 데스크톱 코드와의 호환성을 위해
        /// 호출은 허용하되 경고 로그를 남긴다.
        public func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            _ = (width, height)
            try await ensureHandleExists(handle)
            KSLog.logger("platform.ios.window")
                .warning("setSize ignored on iOS (UIKit controls window dimensions)")
        }

        public func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend {
            let host = await MainActor.run {
                KSiOSHandleRegistry.shared.webView(for: handle.label)
            }
            guard let host else {
                throw KSError(
                    code: .webviewInitFailed,
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
                throw KSError(
                    code: .windowCreationFailed,
                    message: "No iOS window registered for label '\(handle.label)'")
            }
        }
    }
#endif
