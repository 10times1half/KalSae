#if os(macOS)
    internal import AppKit
    public import KalsaeCore

    /// macOS implementation of `KSWindowBackend`.
    ///
    /// Operates on `KSMacWindow` instances tracked by `KSMacHandleRegistry`.
    /// The `create(_:)` method produces an NSWindow with an embedded WKWebView
    /// and a fully-wired `WKBridge`.
    public struct KSMacWindowBackend: KSWindowBackend, Sendable {
        public init() {}

        // MARK: - Resolution helpers

        @MainActor
        private func window(for handle: KSWindowHandle) throws(KSError) -> KSMacWindow {
            guard let w = KSMacHandleRegistry.shared.window(for: handle) else {
                throw KSError(
                    code: .windowCreationFailed,
                    message: "No window registered for label '\(handle.label)'")
            }
            return w
        }

        @MainActor
        private func handle(of window: KSMacWindow) -> KSWindowHandle? {
            let raw = UInt64(UInt(bitPattern: ObjectIdentifier(window)))
            return KSWindowHandle(label: window.config.label, rawValue: raw)
        }

        // MARK: - Lifecycle

        public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
            let result: Result<KSWindowHandle, KSError> = await MainActor.run {
                do {
                    let w = try KSMacWindow(config: config)
                    let host = WKWebViewHost(label: config.label)
                    w.webviewHost = host
                    w.setContentView(host.webView)

                    let raw = UInt64(UInt(bitPattern: ObjectIdentifier(w)))
                    let handle = KSWindowHandle(label: config.label, rawValue: raw)
                    KSMacHandleRegistry.shared.register(label: config.label, rawValue: raw, window: w)

                    if config.visible {
                        w.show()
                    }
                    return .success(handle)
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            return try result.unwrap()
        }

        public func close(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.close() }
            await MainActor.run {
                KSMacHandleRegistry.shared.unregister(label: handle.label)
            }
        }

        public func show(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.show() }
        }

        public func hide(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.hide() }
        }

        public func focus(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.focus() }
        }

        public func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {
            try await runMain(handle) { $0.setTitle(title) }
        }

        public func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            try await runMain(handle) { $0.setSize(width: width, height: height) }
        }

        public func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend {
            let w = try await resolve(handle)
            guard let host = w.webviewHost else {
                throw KSError(
                    code: .webviewInitFailed,
                    message: "WebView not initialised for window '\(handle.label)'")
            }
            return host
        }

        public func all() async -> [KSWindowHandle] {
            await MainActor.run {
                KSMacHandleRegistry.shared.allWindows().compactMap { handle(of: $0) }
            }
        }

        public func find(label: String) async -> KSWindowHandle? {
            await MainActor.run {
                KSMacHandleRegistry.shared.handle(for: label)
            }
        }

        // MARK: - State

        public func minimize(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.minimize() }
        }

        public func maximize(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.maximize() }
        }

        public func restore(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.restore() }
        }

        public func toggleMaximize(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.toggleMaximize() }
        }

        public func isMinimized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
            try await queryMain(handle) { $0.isMinimized() }
        }

        public func isMaximized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
            try await queryMain(handle) { $0.isMaximized() }
        }

        public func isFullscreen(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
            try await queryMain(handle) { $0.isFullscreen() }
        }

        public func setFullscreen(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
            try await runMain(handle) { $0.setFullscreen(enabled) }
        }

        public func setAlwaysOnTop(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
            try await runMain(handle) { $0.setAlwaysOnTop(enabled) }
        }

        public func center(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.centerOnScreen() }
        }

        public func setPosition(_ handle: KSWindowHandle, x: Int, y: Int) async throws(KSError) {
            try await runMain(handle) { $0.setPosition(x: x, y: y) }
        }

        public func getPosition(_ handle: KSWindowHandle) async throws(KSError) -> KSPoint {
            try await queryMain(handle) { $0.getPosition() }
        }

        public func getSize(_ handle: KSWindowHandle) async throws(KSError) -> KSSize {
            try await queryMain(handle) { $0.getSize() }
        }

        public func setMinSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            try await runMain(handle) { $0.setMinSize(width: width, height: height) }
        }

        public func setMaxSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            try await runMain(handle) { $0.setMaxSize(width: width, height: height) }
        }

        public func reload(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.reload() }
        }

        public func setTheme(_ handle: KSWindowHandle, theme: KSWindowTheme) async throws(KSError) {
            try await runMain(handle) { $0.setTheme(theme) }
        }

        public func setBackgroundColor(_ handle: KSWindowHandle, rgba: UInt32) async throws(KSError) {
            try await runMain(handle) { $0.setBackgroundColor(rgba: rgba) }
        }

        public func setCloseInterceptor(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
            try await runMain(handle) { $0.setCloseInterceptor(enabled) }
        }

        public func setZoomFactor(_ handle: KSWindowHandle, factor: Double) async throws(KSError) {
            try await runMain(handle) { $0.webviewHost?.setZoomFactor(factor) }
        }

        public func getZoomFactor(_ handle: KSWindowHandle) async throws(KSError) -> Double {
            try await queryMain(handle) { $0.webviewHost?.getZoomFactor() ?? 1.0 }
        }

        public func showPrintUI(_ handle: KSWindowHandle, systemDialog: Bool) async throws(KSError) {
            try await runMain(handle) { $0.webviewHost?.showPrintUI(systemDialog: systemDialog) }
        }

        public func capturePreview(_ handle: KSWindowHandle, format: Int32) async throws(KSError) -> Data {
            let host: WKWebViewHost? = try await queryMain(handle) { $0.webviewHost }
            guard let host else {
                throw KSError(
                    code: .webviewInitFailed,
                    message: "capturePreview: webview not initialised")
            }
            return try await host.capturePreview(format: format)
        }

        // MARK: - Internals

        @MainActor
        private func resolve(_ handle: KSWindowHandle) throws(KSError) -> KSMacWindow {
            try window(for: handle)
        }

        private func runMain(
            _ handle: KSWindowHandle,
            _ body: @MainActor @Sendable (KSMacWindow) throws(KSError) -> Void
        ) async throws(KSError) {
            let result: Result<Void, KSError> = await MainActor.run {
                do {
                    let w = try self.window(for: handle)
                    try body(w)
                    return .success(())
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            try result.unwrap()
        }

        private func queryMain<T: Sendable>(
            _ handle: KSWindowHandle,
            _ body: @MainActor @Sendable (KSMacWindow) throws(KSError) -> T
        ) async throws(KSError) -> T {
            let result: Result<T, KSError> = await MainActor.run {
                do {
                    let w = try self.window(for: handle)
                    return .success(try body(w))
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            return try result.unwrap()
        }
    }
#endif
