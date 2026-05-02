#if os(Android)
    public import KalsaeCore
    public import Foundation

    // 지원하는 최소 Android API 레벨: 26 (Android 8 Oreo).
    // 타겟 Android API 레벨:            35 (Android 15).
    // 크로스 컴파일 타겟: aarch64-unknown-linux-android26 (또는 에뮬레이터용 x86_64-linux-android26).
    // JNI 진입점은 Sources/KalsaePlatformAndroid/JNI/에 위치한다.
    // @unchecked: NSLock-guarded mutable state — actor unsuitable for platform backend
    public final class KSAndroidPlatform: KSPlatform, @unchecked Sendable {
        /// 지원하는 최소 Android API 레벨 (minSdk 26 = Android 8 Oreo).
        public static let minimumAPILevel: Int = 26
        /// 타겟 Android API 레벨 (targetSdk 35 = Android 15).
        public static let targetAPILevel: Int = 35

        public var name: String { "Android (Preview, API \(Self.minimumAPILevel)+)" }

        public let commandRegistry: KSCommandRegistry

        public var windows: any KSWindowBackend { _windows }
        public var dialogs: any KSDialogBackend { _dialogs }
        public var tray: (any KSTrayBackend)? { nil }
        public var menus: any KSMenuBackend { _menus }
        public var notifications: any KSNotificationBackend { _notifications }
        public var shell: (any KSShellBackend)? { _shell }
        public var clipboard: (any KSClipboardBackend)? { _clipboard }
        public var accelerators: (any KSAcceleratorBackend)? { nil }
        public var autostart: (any KSAutostartBackend)? { _autostart }
        public var deepLink: (any KSDeepLinkBackend)? { _deepLink }

        private let _windows: KSAndroidWindowBackend
        private let _dialogs: KSAndroidDialogBackend
        private let _menus: KSAndroidMenuBackend
        private let _notifications: KSAndroidNotificationBackend
        public let _shell: KSAndroidShellBackend
        public let _clipboard: KSAndroidClipboardBackend
        private let _autostart: KSAndroidAutostartBackend
        private let _deepLink: KSAndroidDeepLinkBackend

        public init() {
            self.commandRegistry = KSCommandRegistry()
            self._windows = KSAndroidWindowBackend()
            self._dialogs = KSAndroidDialogBackend()
            self._menus = KSAndroidMenuBackend()
            self._notifications = KSAndroidNotificationBackend()
            self._shell = KSAndroidShellBackend()
            self._clipboard = KSAndroidClipboardBackend()
            self._autostart = KSAndroidAutostartBackend()
            self._deepLink = KSAndroidDeepLinkBackend(
                identifier: Bundle.main.bundleIdentifier ?? "kalsae")
        }

        public func run(
            config: KSConfig,
            configure: @Sendable (any KSPlatform) async throws(KSError) -> Void
        ) async throws(KSError) -> Never {
            _ = config
            try await configure(self)
            throw KSError.unsupportedPlatform(
                "KSAndroidPlatform.run() is permanently unsupported — Android lifecycle "
                    + "is JVM/Activity-controlled. Use KSApp.boot() + KSAndroidDemoHost instead.")
        }
    }

    public struct KSAndroidWindowBackend: KSWindowBackend, Sendable {
        private actor Registry {
            var handlesByLabel: [String: KSWindowHandle] = [:]
            var webViewsByLabel: [String: KSAndroidWebViewHost] = [:]

            func create(label: String) -> KSWindowHandle {
                let handle = KSWindowHandle(label: label, rawValue: UInt64.random(in: 1...UInt64.max))
                handlesByLabel[label] = handle
                return handle
            }

            func close(_ handle: KSWindowHandle) {
                handlesByLabel.removeValue(forKey: handle.label)
                webViewsByLabel.removeValue(forKey: handle.label)
            }

            func find(label: String) -> KSWindowHandle? {
                handlesByLabel[label]
            }

            func all() -> [KSWindowHandle] {
                Array(handlesByLabel.values)
            }

            func exists(_ handle: KSWindowHandle) -> Bool {
                handlesByLabel[handle.label] != nil
            }

            func registerWebView(_ host: KSAndroidWebViewHost, for label: String) {
                webViewsByLabel[label] = host
            }

            func webView(for label: String) -> KSAndroidWebViewHost? {
                webViewsByLabel[label]
            }
        }

        private let registry = Registry()

        public init() {}

        public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
            await registry.create(label: config.label)
        }

        public func close(_ handle: KSWindowHandle) async throws(KSError) {
            await registry.close(handle)
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
            if let host = await registry.webView(for: handle.label) {
                return host
            }
            throw KSError(
                code: .webviewInitFailed,
                message: "WebView not registered for window '\(handle.label)'")
        }

        /// Kotlin Activity 호스트가 WebView 호스트를 등록하기 위해 호출한다.
        public func registerWebView(_ host: KSAndroidWebViewHost, for label: String) async {
            await registry.registerWebView(host, for: label)
        }

        public func all() async -> [KSWindowHandle] {
            await registry.all()
        }

        public func find(label: String) async -> KSWindowHandle? {
            await registry.find(label: label)
        }

        private func ensureHandleExists(_ handle: KSWindowHandle) async throws(KSError) {
            let exists = await registry.exists(handle)
            if !exists {
                throw KSError(
                    code: .windowCreationFailed,
                    message: "No Android window registered for label '\(handle.label)'")
            }
        }
    }

    // @unchecked: JNI + main thread binding — actor unsuitable for JVM thread affinity
    public final class KSAndroidNotificationBackend: KSNotificationBackend, @unchecked Sendable {
        private let lock = NSLock()

        /// Kotlin에서 주입: `backend.onRequestPermission = { ... }`.
        /// 클로저는 `ActivityCompat.requestPermissions`를 호출하고
        /// 반환하기 전에 `KSAndroidPermissions.shared`를 업데이트해야 한다.
        public var onRequestPermission: (() async -> Bool)? {
            get { lock.withLock { _onRequestPermission } }
            set { lock.withLock { _onRequestPermission = newValue } }
        }
        private var _onRequestPermission: (() async -> Bool)?

        /// 시스템 알림을 전달하도록 Kotlin에서 주입한다.
        public var onPost: ((KSNotification) async -> Bool)? {
            get { lock.withLock { _onPost } }
            set { lock.withLock { _onPost = newValue } }
        }
        private var _onPost: ((KSNotification) async -> Bool)?

        public init() {}

        public func requestPermission() async -> Bool {
            // 먼저 권한 레지스트리를 확인한다 — 이미 허용된 상태일 수 있다.
            if KSAndroidPermissions.shared.isGranted("POST_NOTIFICATIONS") { return true }
            if let handler = lock.withLock({ _onRequestPermission }) {
                return await handler()
            }
            return false
        }

        public func post(_ notification: KSNotification) async throws(KSError) {
            guard let handler = lock.withLock({ _onPost }) else {
                throw KSError.unsupportedPlatform(
                    "Notifications.post: Android bridge not installed")
            }
            let accepted = await handler(notification)
            if !accepted {
                throw KSError(
                    code: .unsupportedPlatform,
                    message: "Notification '\(notification.id)' was rejected by Android")
            }
        }

        public func cancel(id: String) async {
            _ = id
            // 취소는 NotificationManager가 필요함 — JNI 훅 단계로 연기.
        }
    }
#endif
