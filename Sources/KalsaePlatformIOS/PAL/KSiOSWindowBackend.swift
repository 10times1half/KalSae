#if os(iOS)
    internal import UIKit
    public import KalsaeCore
    public import Foundation

    /// 라벨로 등록된 윈도우 핸들과 (있으면) 실제 `UIWindow` /
    /// `KSiOSWebViewHost`를 추적하는 `@MainActor` 보호 레지스트리입니다.
    ///
    /// iOS에서는 `KSiOSDemoHost`가 부팅 흐름에서 메인 윈도우를 등록하고,
    /// `KSiOSAppDelegate.didFinishLaunching` 시점에 실제 `UIWindow`을 연결합니다.
    /// `KSiOSWindowBackend`는 등록된 `UIWindow`이 있으면 그 위에서
    /// show/hide/focus/setTitle 동작을 수행합니다.
    ///
    /// iOS는 데스크톱과 달리 멀티 윈도우를 기본적으로 지원하지 않지만,
    /// iPadOS 13+의 `UIScene` 멀티 윈도우를 통해 여러 윈도우를 만들 수 있습니다.
    /// 현재 구현은 기본적인 단일 윈도우 시나리오를 지원합니다.
    @MainActor
    internal final class KSiOSHandleRegistry {
        /// 전역 싱글톤 인스턴스입니다.
        static let shared = KSiOSHandleRegistry()

        private var byLabel: [String: KSWindowHandle] = [:]
        private var webViewByLabel: [String: KSiOSWebViewHost] = [:]
        private var windowByLabel: [String: UIWindow] = [:]

        /// 새 윈도우 핸들을 등록하고 반환합니다.
        /// - Parameter label: 등록할 윈도우 라벨 (고유 식별자)
        /// - Returns: 생성된 `KSWindowHandle`
        func register(label: String) -> KSWindowHandle {
            let raw = UInt64.random(in: 1...UInt64.max)
            let handle = KSWindowHandle(label: label, rawValue: raw)
            byLabel[label] = handle
            return handle
        }

        /// 특정 라벨에 WebView 호스트를 연결합니다.
        /// - Parameters:
        ///   - host: 등록할 WebView 호스트
        ///   - label: 대상 윈도우 라벨
        func registerWebView(_ host: KSiOSWebViewHost, for label: String) {
            webViewByLabel[label] = host
        }

        /// `KSiOSAppDelegate`가 호출합니다. 메인 윈도우의 `UIWindow`을
        /// 핸들 레이블에 연결해 백엔드에서 show/hide/focus 등을 수행할 수
        /// 있게 합니다.
        /// - Parameters:
        ///   - window: 등록할 `UIWindow` 인스턴스
        ///   - label: 대상 윈도우 라벨
        func registerWindow(_ window: UIWindow, for label: String) {
            windowByLabel[label] = window
        }

        /// 윈도우 핸들과 연결된 모든 리소스를 등록 해제합니다.
        /// - Parameter handle: 해제할 윈도우 핸들
        func unregister(_ handle: KSWindowHandle) {
            byLabel.removeValue(forKey: handle.label)
            webViewByLabel.removeValue(forKey: handle.label)
            windowByLabel.removeValue(forKey: handle.label)
        }

        /// 특정 라벨의 윈도우 핸들을 반환합니다.
        /// - Parameter label: 조회할 윈도우 라벨
        /// - Returns: 등록된 `KSWindowHandle` (없으면 `nil`)
        func handle(for label: String) -> KSWindowHandle? {
            byLabel[label]
        }

        /// 특정 라벨의 WebView 호스트를 반환합니다.
        func webView(for label: String) -> KSiOSWebViewHost? {
            webViewByLabel[label]
        }

        /// 특정 라벨의 `UIWindow`를 반환합니다.
        func window(for label: String) -> UIWindow? {
            windowByLabel[label]
        }

        /// 등록된 모든 윈도우 핸들을 반환합니다.
        /// - Returns: 등록된 `KSWindowHandle` 배열
        func all() -> [KSWindowHandle] {
            Array(byLabel.values)
        }
    }

    /// iOS용 윈도우 관리 `KSWindowBackend` 구현체입니다.
    ///
    /// iOS는 데스크톱식 멀티 윈도우 모델이 없습니다. 메인 윈도우는
    /// `KSiOSDemoHost`가 부팅 흐름에서 등록하고 `KSiOSAppDelegate`가 실제
    /// `UIWindow`을 연결합니다.
    ///
    /// 주요 동작:
    /// - `create()`: **논리적 핸들만** 등록합니다. 실제 추가 `UIWindow`은
    ///   멀티 씬을 지원하기 전까지는 생성되지 않습니다.
    /// - `show/hide/focus/setTitle`: 등록된 `UIWindow`이 있을 때만 동작합니다.
    /// - `setSize`: UIKit이 화면/씬 크기를 통제하므로 무시되며 경고 로그만 남깁니다.
    public struct KSiOSWindowBackend: KSWindowBackend, Sendable {
        public init() {}

        /// 새 윈도우를 생성합니다.
        /// iOS에서는 논리적 핸들만 등록합니다. 실제 `UIWindow`는
        /// `KSiOSAppDelegate`가 추후 연결합니다.
        /// - Parameter config: 윈도우 설정 (라벨, 크기 등)
        /// - Returns: 생성된 `KSWindowHandle` (이미 존재하는 라벨이면 기존 핸들)
        /// - Throws: 오류를 던지지 않음
        public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
            await MainActor.run {
                if let existing = KSiOSHandleRegistry.shared.handle(for: config.label) {
                    return existing
                }
                return KSiOSHandleRegistry.shared.register(label: config.label)
            }
        }

        /// 윈도우를 닫고 등록을 해제합니다.
        /// 실제 `UIWindow`가 있으면 숨기고, 핸들과 WebView/이벤트 허브를
        /// 모두 정리합니다.
        /// - Parameter handle: 닫을 윈도우 핸들
        /// - Throws: 오류를 던지지 않음
        public func close(_ handle: KSWindowHandle) async throws(KSError) {
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.isHidden = true
                }
                KSiOSHandleRegistry.shared.unregister(handle)
                KSWindowEmitHub.shared.unregister(label: handle.label)
            }
        }

        /// 윈도우를 표시합니다.
        /// - Parameter handle: 표시할 윈도우 핸들
        /// - Throws: 핸들이 등록되지 않았으면 `code: .windowCreationFailed`
        public func show(_ handle: KSWindowHandle) async throws(KSError) {
            try await ensureHandleExists(handle)
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.makeKeyAndVisible()
                }
            }
        }

        /// 윈도우를 숨깁니다.
        /// - Parameter handle: 숨길 윈도우 핸들
        /// - Throws: 핸들이 등록되지 않았으면 `code: .windowCreationFailed`
        public func hide(_ handle: KSWindowHandle) async throws(KSError) {
            try await ensureHandleExists(handle)
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.isHidden = true
                }
            }
        }

        /// 윈도우에 포커스를 줍니다.
        /// - Parameter handle: 포커스할 윈도우 핸들
        /// - Throws: 핸들이 등록되지 않았으면 `code: .windowCreationFailed`
        public func focus(_ handle: KSWindowHandle) async throws(KSError) {
            try await ensureHandleExists(handle)
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.makeKey()
                }
            }
        }

        /// 윈도우 제목을 설정합니다.
        /// iOS 13+에서는 `UIWindowScene.title`을 설정합니다.
        /// - Parameters:
        ///   - handle: 대상 윈도우 핸들
        ///   - title: 새 제목
        /// - Throws: 핸들이 등록되지 않았으면 `code: .windowCreationFailed`
        public func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {
            try await ensureHandleExists(handle)
            await MainActor.run {
                if let win = KSiOSHandleRegistry.shared.window(for: handle.label) {
                    win.windowScene?.title = title
                }
            }
        }

        /// 윈도우 크기를 설정합니다.
        /// iOS는 사용자가 윈도우 크기를 프로그래매틱하게 변경하는 개념이
        /// 없습니다 (UIKit이 화면/씬 크기를 통제). 데스크톱 코드와의
        /// 호환성을 위해 호출은 허용하되 경고 로그를 남깁니다.
        /// - Parameters:
        ///   - handle: 대상 윈도우 핸들
        ///   - width: 요청할 너비 (iOS에서 무시됨)
        ///   - height: 요청할 높이 (iOS에서 무시됨)
        /// - Throws: 핸들이 등록되지 않았으면 `code: .windowCreationFailed`
        public func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            _ = (width, height)
            try await ensureHandleExists(handle)
            KSLog.logger("platform.ios.window")
                .warning("setSize ignored on iOS (UIKit controls window dimensions)")
        }

        /// 특정 윈도우 핸들에 연결된 WebView 백엔드를 반환합니다.
        /// - Parameter handle: 대상 윈도우 핸들
        /// - Returns: `KSWebViewBackend` 프로토콜을 준수하는 WebView 호스트
        /// - Throws: WebView가 초기화되지 않았으면 `code: .webviewInitFailed`
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

        /// 등록된 모든 윈도우 핸들을 반환합니다.
        /// - Returns: 현재 등록된 모든 `KSWindowHandle` 배열
        public func all() async -> [KSWindowHandle] {
            await MainActor.run {
                KSiOSHandleRegistry.shared.all()
            }
        }

        /// 특정 라벨의 윈도우 핸들을 찾습니다.
        /// - Parameter label: 찾을 윈도우 라벨
        /// - Returns: 해당 라벨의 `KSWindowHandle` (없으면 `nil`)
        public func find(label: String) async -> KSWindowHandle? {
            await MainActor.run {
                KSiOSHandleRegistry.shared.handle(for: label)
            }
        }

        /// 윈도우 핸들이 레지스트리에 존재하는지 확인합니다.
        /// - Parameter handle: 확인할 윈도우 핸들
        /// - Throws: 등록되지 않았으면 `code: .windowCreationFailed`
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
