#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    public import Foundation

    /// Windows implementation of `KSWindowBackend`.
    ///
    /// Operates on the set of `Win32Window` instances tracked by `Win32App`
    /// and `KSWin32HandleRegistry`. The `KSWindowsDemoHost`'s primary
    /// window is registered through that path, so all of the state APIs
    /// (minimize/maximize/center/setPosition/setAlwaysOnTop/...) work
    /// against it out of the box.
    ///
    /// Each window owns its own `WebView2Host` and `WebView2Bridge`. All
    /// lifecycle and geometry operations are functional.
    public struct KSWindowsWindowBackend: KSWindowBackend, Sendable {
        private let registry: KSCommandRegistry

        public init(registry: KSCommandRegistry = KSCommandRegistry()) {
            self.registry = registry
        }

        // MARK: - Resolution helpers

        @MainActor
        private func window(for handle: KSWindowHandle) throws(KSError) -> Win32Window {
            guard let hwnd = KSWin32HandleRegistry.shared.hwnd(for: handle) else {
                throw KSError(
                    code: .windowCreationFailed,
                    message: "No window registered for label '\(handle.label)'")
            }
            guard let win = Win32App.shared.window(for: hwnd) else {
                throw KSError(
                    code: .windowCreationFailed,
                    message: "Win32Window not tracked for label '\(handle.label)'")
            }
            return win
        }

        @MainActor
        private func handle(of window: Win32Window) -> KSWindowHandle? {
            guard let hwnd = window.hwnd else { return nil }
            let raw = UInt64(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd))))
            return KSWindowHandle(label: window.label, rawValue: raw)
        }

        // MARK: - Lifecycle

        public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
            let result: Result<KSWindowHandle, KSError> = await MainActor.run {
                do {
                    try Win32App.shared.ensureCOMInitialized()

                    let window = try Win32Window(config: config)
                    guard let hwnd = window.hwnd else {
                        throw KSError(
                            code: .windowCreationFailed,
                            message: "Window has no HWND")
                    }

                    let webview = WebView2Host(label: config.label)
                    let bridge = WebView2Bridge(host: webview, registry: registry, windowLabel: config.label)
                    let bridgeRef = bridge
                    window.eventSink = { name, payload in
                        try? bridgeRef.emit(event: name, payload: payload)
                    }

                    do {
                        try webview.initialize(
                            hwnd: hwnd,
                            devtools: false,
                            userDataFolderOverride: config.webview?.userDataPath)
                        window.attach(host: webview)
                        try bridge.install()
                        applyVisualOptions(window: window, webview: webview, options: config.webview)
                    } catch {
                        webview.dispose()
                        window.close()
                        throw error
                    }

                    guard let handle = handle(of: window) else {
                        throw KSError(
                            code: .windowCreationFailed,
                            message: "Failed to resolve handle for '\(config.label)'")
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
            let result: Result<Void, KSError> = await MainActor.run {
                // `MainActor.run` 클로저 내부는 typed-throws 추론이 적용되지
                // 않으므로 `as? KSError`로 명시 캐스팅한다. window(for:)는
                // KSError만 엔젯한다.
                do {
                    let w = try self.window(for: handle)
                    w.close()
                    return .success(())
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            try result.unwrap()
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
            let host: WebView2Host? = try await queryMain(handle) { $0.webviewHost }
            guard let host else {
                throw KSError(
                    code: .webviewInitFailed,
                    message: "WebView not initialised for window '\(handle.label)'")
            }
            return host
        }

        public func all() async -> [KSWindowHandle] {
            await MainActor.run {
                Win32App.shared.allWindows().compactMap { handle(of: $0) }
            }
        }

        public func find(label: String) async -> KSWindowHandle? {
            await MainActor.run {
                KSWin32HandleRegistry.shared.handle(for: label)
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
            try await queryMain(handle) {
                let p = $0.getPosition()
                return KSPoint(x: Double(p.x), y: Double(p.y))
            }
        }

        public func getSize(_ handle: KSWindowHandle) async throws(KSError) -> KSSize {
            try await queryMain(handle) {
                let s = $0.getSize()
                return KSSize(width: s.width, height: s.height)
            }
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
            // 동기 hop으로 host 핸들을 가져온 뒤, async 호출은 main-actor
            // 안에서 직접 await 한다. (host 자체가 @MainActor 격리.)
            let host: WebView2Host? = try await queryMain(handle) { $0.webviewHost }
            guard let host else {
                throw KSError(
                    code: .webviewInitFailed,
                    message: "capturePreview: webview not initialised")
            }
            let fmt = WebView2Host.CaptureFormat(rawValue: format) ?? .png
            do {
                return try await host.capturePreview(format: fmt)
            } catch {
                throw error
            }
        }

        // MARK: - Internals

        @MainActor
        private func applyVisualOptions(
            window: Win32Window,
            webview: WebView2Host,
            options: KSWebViewOptions?
        ) {
            if let backdrop = options?.backdropType {
                window.setSystemBackdrop(backdrop)
            }
            guard let options else { return }
            if options.transparent {
                webview.setDefaultBackgroundColor(KSColorRGBA(r: 0, g: 0, b: 0, a: 0))
            }
            if options.disablePinchZoom {
                webview.setPinchZoomEnabled(false)
            }
            if let z = options.zoomFactor {
                webview.setZoomFactor(z)
            }
        }

        private func runMain(
            _ handle: KSWindowHandle,
            _ body: @MainActor @Sendable (Win32Window) -> Void
        ) async throws(KSError) {
            let result: Result<Void, KSError> = await MainActor.run {
                do {
                    let w = try self.window(for: handle)
                    body(w)
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
            _ body: @MainActor @Sendable (Win32Window) -> T
        ) async throws(KSError) -> T {
            let result: Result<T, KSError> = await MainActor.run {
                do {
                    let w = try self.window(for: handle)
                    return .success(body(w))
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
