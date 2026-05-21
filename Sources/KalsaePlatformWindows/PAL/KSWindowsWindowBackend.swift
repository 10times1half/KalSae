#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    public import Foundation

    // MARK: - KSWindowsWindowBackend

    /// Windows `KSWindowBackend` 구현체.
    ///
    /// `Win32App`과 `KSWin32HandleRegistry`가 추적하는 `Win32Window`
    /// 인스턴스 집합에 대해 동작한다. `KSWindowsDemoHost`의 기본 윈도우는
    /// 이 경로를 통해 등록되므로, 모든 상태 API(minimize/maximize/center/
    /// setPosition/setAlwaysOnTop/...)가 별도 설정 없이 동작한다.
    ///
    /// 각 윈도우는 자체 `WebView2Host`와 `WebView2Bridge`를 소유한다.
    /// 생명주기 및 지오메트리 연산은 모두 기능적(functional)이다.
    ///
    /// ## 주의: `await MainActor.run` 사용 금지
    ///
    /// 이 백엔드는 `await MainActor.run`을 통해 `@MainActor`로 hop하지
    /// 않는다. Kalsae의 Win32 호스트는 전용 UI 스레드에서 메시지 루프를
    /// 실행하고, Swift 메인 스레드는 `WaitForSingleObject(uiThread)`로
    /// 영구 블록된다. 따라서 `await MainActor.run`은 절대 resume되지
    /// 않으며 모든 JS-bridge 호출이 IPC 30초 타임아웃까지 데드락된다.
    ///
    /// 대신 `Win32App.runOnUIThreadIsolated`를 사용해 실제 Win32 UI
    /// 스레드로 동기 디스패치한다.
    public struct KSWindowsWindowBackend: KSWindowBackend, Sendable {
        private let registry: KSCommandRegistry

        public init(registry: KSCommandRegistry = KSCommandRegistry()) {
            self.registry = registry
        }

        // MARK: - 핸들/윈도우 resolution 헬퍼

        /// `KSWindowHandle`에 대응하는 `Win32Window` 인스턴스를 반환한다.
        ///
        /// 조회 순서:
        /// 1. `KSWin32HandleRegistry.shared.hwnd(for:)` → HWND
        /// 2. `Win32App.shared.window(for:)` → Win32Window
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

        /// `Win32Window` → `KSWindowHandle` 변환.
        /// HWND의 포인터 값을 `UInt64` rawValue로 사용한다.
        @MainActor
        private func handle(of window: Win32Window) -> KSWindowHandle? {
            guard let hwnd = window.hwnd else { return nil }
            let raw = UInt64(UInt(bitPattern: Int(bitPattern: UnsafeRawPointer(hwnd))))
            return KSWindowHandle(label: window.label, rawValue: raw)
        }

        // MARK: - 생명주기 (Lifecycle)

        /// 새 윈도우를 생성한다.
        ///
        /// 1. `Win32App.shared.ensureCOMInitialized()` — COM 초기화 보장
        /// 2. `Win32Window(config:)` — Win32 윈도우 생성 (RegisterClass + CreateWindowEx)
        /// 3. `WebView2Host(label:)` + `WebView2Bridge` 생성
        /// 4. `webview.initialize(hwnd:, ...)` — WebView2 환경/컨트롤 초기화
        /// 5. `bridge.install()` — IPC 브리지 설치
        /// 6. `KSWindowsBridgeRegistry.shared.register(...)` — bridge 명시적 retain
        /// 7. `applyVisualOptions(...)` — backdrop/투명/줌 설정 적용
        ///
        /// 실패 시 webview와 window를 정리한 후 에러를 전파한다.
        public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
            let result: Result<KSWindowHandle, KSError> = Win32App.runOnUIThreadIsolated {
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
                            userDataFolderOverride: config.webview?.userDataPath,
                            envOptions: config.webview?.platform?.windows,
                            preferences: config.webview?.preferences)
                        window.attach(host: webview)
                        try bridge.install()
                        // 명시적 retain — eventSink 클로저 캡처에만 의존하면
                        // eventSink 교체 시 bridge가 즉시 deinit된다.
                        KSWindowsBridgeRegistry.shared.register(
                            label: config.label, bridge: bridge)
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

        /// 윈도우를 닫고 브리지 등록을 해제한다.
        /// 내부적으로 `Win32Window.close()`를 호출하여
        /// `DestroyWindow` → `WM_DESTROY` → `Win32Window.windowProc` 정리 경로를 실행한다.
        public func close(_ handle: KSWindowHandle) async throws(KSError) {
            let result: Result<Void, KSError> = Win32App.runOnUIThreadIsolated {
                // `runOnUIThreadIsolated` 클로저 내부는 typed-throws 추론이 적용되지
                // 않으므로 `as? KSError`로 명시 캐스팅한다.
                do {
                    let w = try self.window(for: handle)
                    w.close()
                    KSWindowsBridgeRegistry.shared.unregister(label: handle.label)
                    return .success(())
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            try result.unwrap()
        }

        // MARK: - 표시 (Show/Hide/Focus)

        /// 윈도우를 표시한다 (`ShowWindow(SW_SHOW)`).
        public func show(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.show() }
        }

        /// 윈도우를 숨긴다 (`ShowWindow(SW_HIDE)`).
        public func hide(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.hide() }
        }

        /// 윈도우에 포커스를 설정한다 (`SetFocus` / `SetForegroundWindow`).
        public func focus(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.focus() }
        }

        /// 윈도우 제목을 설정한다 (`SetWindowTextW`).
        public func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {
            try await runMain(handle) { $0.setTitle(title) }
        }

        /// 윈도우 클라이언트 영역의 크기를 설정한다 (`SetWindowPos`).
        public func setSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            try await runMain(handle) { $0.setSize(width: width, height: height) }
        }

        /// 윈도우에 연결된 `WebView2Host`를 `KSWebViewBackend`로 반환한다.
        public func webView(for handle: KSWindowHandle) async throws(KSError) -> any KSWebViewBackend {
            let host: WebView2Host? = try await queryMain(handle) { $0.webviewHost }
            guard let host else {
                throw KSError(
                    code: .webviewInitFailed,
                    message: "WebView not initialised for window '\(handle.label)'")
            }
            return host
        }

        /// 등록된 모든 윈도우의 핸들 목록을 반환한다.
        /// `Array.compactMap` 대신 명시적 for-loop를 사용하는 이유는
        /// stdlib 제네릭이 `@MainActor` 클로저를 추론하면 Win32 UI
        /// 스레드에서 `dispatch_assert_queue` 트랩이 발생하기 때문이다.
        public func all() async -> [KSWindowHandle] {
            Win32App.runOnUIThreadIsolated {
                var out: [KSWindowHandle] = []
                for w in Win32App.shared.allWindows() {
                    if let h = handle(of: w) { out.append(h) }
                }
                return out
            }
        }

        /// 레이블로 윈도우 핸들을 찾는다.
        /// `KSWin32HandleRegistry.shared.handle(for:)`를 통해 O(1) 조회한다.
        public func find(label: String) async -> KSWindowHandle? {
            Win32App.runOnUIThreadIsolated {
                KSWin32HandleRegistry.shared.handle(for: label)
            }
        }

        // MARK: - 윈도우 상태

        /// 윈도우를 최소화한다 (`ShowWindow(SW_MINIMIZE)`).
        public func minimize(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.minimize() }
        }

        /// 윈도우를 최대화한다 (`ShowWindow(SW_MAXIMIZE)`).
        public func maximize(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.maximize() }
        }

        /// 윈도우를 이전 상태(복원)로 되돌린다 (`ShowWindow(SW_RESTORE)`).
        public func restore(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.restore() }
        }

        /// 최대화 상태를 토글한다.
        public func toggleMaximize(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.toggleMaximize() }
        }

        /// 최소화 상태인지 확인한다 (`IsIconic`).
        public func isMinimized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
            try await queryMain(handle) { $0.isMinimized() }
        }

        /// 최대화 상태인지 확인한다 (`IsZoomed`).
        public func isMaximized(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
            try await queryMain(handle) { $0.isMaximized() }
        }

        /// 전체 화면 상태인지 확인한다.
        public func isFullscreen(_ handle: KSWindowHandle) async throws(KSError) -> Bool {
            try await queryMain(handle) { $0.isFullscreen() }
        }

        /// 전체 화면 모드를 설정/해제한다.
        public func setFullscreen(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
            try await runMain(handle) { $0.setFullscreen(enabled) }
        }

        /// 항상 위(always-on-top) 플래그를 설정/해제한다
        /// (`SetWindowPos(HWND_TOPMOST / HWND_NOTOPMOST)`).
        public func setAlwaysOnTop(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
            try await runMain(handle) { $0.setAlwaysOnTop(enabled) }
        }

        /// 윈도우를 화면 중앙에 배치한다
        /// (`MonitorFromWindow` + `CalculateWindowRect` + `SetWindowPos`).
        public func center(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.centerOnScreen() }
        }

        /// 윈도우 위치를 설정한다 (`SetWindowPos`).
        public func setPosition(_ handle: KSWindowHandle, x: Int, y: Int) async throws(KSError) {
            try await runMain(handle) { $0.setPosition(x: x, y: y) }
        }

        /// 윈도우 위치를 반환한다 (`GetWindowRect`).
        public func getPosition(_ handle: KSWindowHandle) async throws(KSError) -> KSPoint {
            try await queryMain(handle) {
                let p = $0.getPosition()
                return KSPoint(x: Double(p.x), y: Double(p.y))
            }
        }

        /// 윈도우 크기를 반환한다.
        public func getSize(_ handle: KSWindowHandle) async throws(KSError) -> KSSize {
            try await queryMain(handle) {
                let s = $0.getSize()
                return KSSize(width: s.width, height: s.height)
            }
        }

        /// 최소 크기를 설정한다 (`WM_GETMINMAXINFO` 처리).
        public func setMinSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            try await runMain(handle) { $0.setMinSize(width: width, height: height) }
        }

        /// 최대 크기를 설정한다.
        public func setMaxSize(_ handle: KSWindowHandle, width: Int, height: Int) async throws(KSError) {
            try await runMain(handle) { $0.setMaxSize(width: width, height: height) }
        }

        /// WebView 콘텐츠를 다시 로드한다.
        public func reload(_ handle: KSWindowHandle) async throws(KSError) {
            try await runMain(handle) { $0.reload() }
        }

        /// 윈도우 테마를 설정한다 (DWM 어두운/밝은 타이틀 바).
        public func setTheme(_ handle: KSWindowHandle, theme: KSWindowTheme) async throws(KSError) {
            try await runMain(handle) { $0.setTheme(theme) }
        }

        /// WebView 배경색을 설정한다.
        public func setBackgroundColor(_ handle: KSWindowHandle, rgba: UInt32) async throws(KSError) {
            try await runMain(handle) { $0.setBackgroundColor(rgba: rgba) }
        }

        /// 닫기 인터셉터를 활성화/비활성화한다. 활성화 시 `WM_CLOSE`가
        /// JS 이벤트로 emit되고 윈도우가 즉시 파괴되지 않는다.
        public func setCloseInterceptor(_ handle: KSWindowHandle, enabled: Bool) async throws(KSError) {
            try await runMain(handle) { $0.setCloseInterceptor(enabled) }
        }

        /// WebView 줌 팩터를 설정한다.
        public func setZoomFactor(_ handle: KSWindowHandle, factor: Double) async throws(KSError) {
            try await runMain(handle) { $0.webviewHost?.setZoomFactor(factor) }
        }

        /// WebView의 현재 줌 팩터를 반환한다.
        public func getZoomFactor(_ handle: KSWindowHandle) async throws(KSError) -> Double {
            try await queryMain(handle) { $0.webviewHost?.getZoomFactor() ?? 1.0 }
        }

        /// WebView 인쇄 UI를 표시한다. `systemDialog`가 true면 시스템
        /// 인쇄 대화상자, false면 WebView 내장 인쇄 미리보기를 사용한다.
        public func showPrintUI(_ handle: KSWindowHandle, systemDialog: Bool) async throws(KSError) {
            try await runMain(handle) { $0.webviewHost?.showPrintUI(systemDialog: systemDialog) }
        }

        /// WebView의 현재 화면을 캡처하여 이미지 데이터로 반환한다.
        ///
        /// 동기 hop으로 `webviewHost` 참조를 가져온 뒤, `capturePreview`
        /// async 메서드를 (host가 @MainActor 격리이므로) 직접 await한다.
        public func capturePreview(_ handle: KSWindowHandle, format: Int32) async throws(KSError) -> Data {
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

        // MARK: - 내부 헬퍼

        /// WebView 시각적 옵션을 적용한다.
        ///
        /// - `backdropType`: `DWM_SYSTEMBACKDROP_TYPE` (Mica, Acrylic 등)
        /// - `transparent`: WebView 배경을 투명(`RGBA(0,0,0,0)`)으로 설정
        /// - `disablePinchZoom`: 핀치 줌 제스처 비활성화
        /// - `zoomFactor`: WebView 콘텐츠 배율 설정
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

        // ─── Win32 UI 스레드 디스패치 헬퍼 ──────────────────────────
        //
        // NOTE: 이 두 헬퍼는 원래 `await MainActor.run`을 통해 hop했지만,
        // Kalsae의 Win32 호스트는 전용 UI 스레드에서 메시지 루프를
        // 실행하는 반면 Swift 메인 스레드는
        // `WaitForSingleObject(uiThread)`로 영구 블록된다. 따라서
        // `await MainActor.run`은 절대 resume되지 않으며 모든 JS-bridge
        // 윈도우 호출이 IPC 30초 타임아웃까지 데드락한다.
        //
        // 대신 `Win32App.runOnUIThreadIsolated`를 통해 실제 Win32 UI
        // 스레드로 동기 디스패치한다.
        // ──────────────────────────────────────────────────────────────

        /// void 반환 윈도우 연산을 UI 스레드에서 실행한다.
        private func runMain(
            _ handle: KSWindowHandle,
            _ body: @MainActor @Sendable (Win32Window) -> Void
        ) async throws(KSError) {
            let result: Result<Void, KSError> = Win32App.runOnUIThreadIsolated {
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

        /// 값을 반환하는 윈도우 연산을 UI 스레드에서 실행한다.
        private func queryMain<T: Sendable>(
            _ handle: KSWindowHandle,
            _ body: @MainActor @Sendable (Win32Window) -> T
        ) async throws(KSError) -> T {
            let result: Result<T, KSError> = Win32App.runOnUIThreadIsolated {
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
