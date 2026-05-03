import Foundation

extension KSBuiltinCommands {
    /// `__ks.window.*` 핸들러를 등록한다 — minimize, maximize, restore,
    /// fullscreen, 위치/크기 조회 및 변경, 테마 등.
    static func registerWindowCommands(
        into registry: KSCommandRegistry,
        windows: any KSWindowBackend,
        resolver: WindowResolver
    ) async {
        await register(registry, "__ks.window.minimize") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.minimize(h)
            return Empty()
        }
        await register(registry, "__ks.window.maximize") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.maximize(h)
            return Empty()
        }
        await register(registry, "__ks.window.restore") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.restore(h)
            return Empty()
        }
        await register(registry, "__ks.window.toggleMaximize") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.toggleMaximize(h)
            return Empty()
        }
        await registerQuery(registry, "__ks.window.isMinimized") { _ throws(KSError) -> Bool in
            let h = try await resolver.resolve(window: nil)
            return try await windows.isMinimized(h)
        }
        await registerQuery(registry, "__ks.window.isMaximized") { _ throws(KSError) -> Bool in
            let h = try await resolver.resolve(window: nil)
            return try await windows.isMaximized(h)
        }
        await registerQuery(registry, "__ks.window.isFullscreen") { _ throws(KSError) -> Bool in
            let h = try await resolver.resolve(window: nil)
            return try await windows.isFullscreen(h)
        }
        await register(registry, "__ks.window.setFullscreen") { (args: BoolArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setFullscreen(h, enabled: args.enabled)
            return Empty()
        }
        await register(registry, "__ks.window.setAlwaysOnTop") { (args: BoolArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setAlwaysOnTop(h, enabled: args.enabled)
            return Empty()
        }
        await register(registry, "__ks.window.center") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.center(h)
            return Empty()
        }
        await register(registry, "__ks.window.setPosition") { (args: PositionArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setPosition(h, x: args.x, y: args.y)
            return Empty()
        }
        await registerQuery(registry, "__ks.window.getPosition") { _ throws(KSError) -> KSPoint in
            let h = try await resolver.resolve(window: nil)
            return try await windows.getPosition(h)
        }
        await registerQuery(registry, "__ks.window.getSize") { _ throws(KSError) -> KSSize in
            let h = try await resolver.resolve(window: nil)
            return try await windows.getSize(h)
        }
        await register(registry, "__ks.window.setSize") { (args: SizeArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setSize(h, width: args.width, height: args.height)
            return Empty()
        }
        await register(registry, "__ks.window.setMinSize") { (args: SizeArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setMinSize(h, width: args.width, height: args.height)
            return Empty()
        }
        await register(registry, "__ks.window.setMaxSize") { (args: SizeArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setMaxSize(h, width: args.width, height: args.height)
            return Empty()
        }
        await register(registry, "__ks.window.setTitle") { (args: TitleArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setTitle(h, title: args.title)
            return Empty()
        }
        await register(registry, "__ks.window.show") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.show(h)
            return Empty()
        }
        await register(registry, "__ks.window.hide") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.hide(h)
            return Empty()
        }
        await register(registry, "__ks.window.focus") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.focus(h)
            return Empty()
        }
        await register(registry, "__ks.window.close") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.close(h)
            return Empty()
        }
        await register(registry, "__ks.window.reload") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.reload(h)
            return Empty()
        }
        await register(registry, "__ks.window.setTheme") { (args: ThemeArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setTheme(h, theme: args.theme)
            return Empty()
        }
        // Wails-style: 단일 RGBA 인자(0~255). 내부적으로 0xRRGGBBAA로 패킹.
        await register(registry, "__ks.window.setBackgroundColor") {
            (args: BackgroundColorArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            let rgba =
                (UInt32(args.r) << 24)
                | (UInt32(args.g) << 16)
                | (UInt32(args.b) << 8)
                | UInt32(args.a)
            try await windows.setBackgroundColor(h, rgba: rgba)
            return Empty()
        }
        // 최소화/최대화/전체화면 어느 상태도 아닐 때 true.
        await registerQuery(registry, "__ks.window.isNormal") { _ throws(KSError) -> Bool in
            let h = try await resolver.resolve(window: nil)
            let mini = try await windows.isMinimized(h)
            let maxi = try await windows.isMaximized(h)
            let full = try await windows.isFullscreen(h)
            return !(mini || maxi || full)
        }
        // 인터셉터가 켜지면 close 버튼/Alt-F4가 즉시 닫지 않고
        // `__ks.window.beforeClose` 이벤트를 발사한다.
        await register(registry, "__ks.window.setCloseInterceptor") { (args: BoolArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setCloseInterceptor(h, enabled: args.enabled)
            return Empty()
        }
        // WebView2 controller 줌 팩터 setter / getter (Phase D2).
        await register(registry, "__ks.window.setZoom") { (args: ZoomFactorArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.setZoomFactor(h, factor: args.factor)
            return Empty()
        }
        await registerQuery(registry, "__ks.window.getZoom") { _ throws(KSError) -> Double in
            let h = try await resolver.resolve(window: nil)
            return try await windows.getZoomFactor(h)
        }
        // 인쇄 UI 표시 (Phase D1).
        await register(registry, "__ks.window.print") { (args: PrintArg) throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: args.window)
            try await windows.showPrintUI(h, systemDialog: args.systemDialog ?? false)
            return Empty()
        }
        // 화면 캡처 → Base64 인코딩된 PNG/JPEG 반환 (Phase D3).
        await registerQuery(registry, "__ks.window.capturePreview") { (args: CaptureArg) throws(KSError) -> String in
            let h = try await resolver.resolve(window: args.window)
            let fmt: Int32 = (args.format?.lowercased() == "jpeg" || args.format?.lowercased() == "jpg") ? 1 : 0
            let data = try await windows.capturePreview(h, format: fmt)
            return data.base64EncodedString()
        }

        // Multi-window: 새 창 생성. JS -> `__KS_.invoke("__ks.window.create", config)`.
        // `url` 필드를 지정하면 생성 즉시 해당 URL로 탐색한다.
        await register(registry, "__ks.window.create") { (args: KSWindowConfig) throws(KSError) -> LabelResult in
            let handle = try await windows.create(args)
            if let urlStr = args.url, let url = URL(string: urlStr) {
                let webview = try await windows.webView(for: handle)
                try await webview.load(url: url)
            }
            // 만들어진 창을 다른 모든 창에 알린다.
            struct CreatedPayload: Encodable { let label: String }
            let r: Result<Void, KSError> = await MainActor.run {
                do {
                    try KSWindowEmitHub.shared.emit(
                        event: "__ks.window.created",
                        payload: CreatedPayload(label: args.label),
                        to: nil)
                    return .success(())
                } catch {
                    return .failure(
                        error as? KSError ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            _ = r  // 이벤트 emit 실패는 창 생성 자체를 실패시키지 않는다.
            return LabelResult(label: args.label)
        }

        // Multi-window: 현재 열린 창 레이블 목록 반환.
        await registerQuery(registry, "__ks.window.list") { _ throws(KSError) -> [WindowInfo] in
            let handles = await windows.all()
            return handles.map { WindowInfo(label: $0.label) }
        }

        // Multi-window: 이 IPC 프레임이 발생한 창 레이블 반환.
        await registerQuery(registry, "__ks.window.current") { _ throws(KSError) -> LabelResult in
            guard let label = KSInvocationContext.windowLabel else {
                throw KSError(code: .invalidArgument, message: "__ks.window.current: no active window context")
            }
            return LabelResult(label: label)
        }

        // Multi-window: 특정 창 또는 모든 창에 이벤트 emit.
        // `target` 미지정 시 브로드캐스트.
        await register(registry, "__ks.window.emit") { (args: WindowEmitArg) throws(KSError) -> Empty in
            let r: Result<Void, KSError> = await MainActor.run {
                do {
                    try KSWindowEmitHub.shared.emit(
                        event: args.event, payload: args.payload, to: args.target)
                    return .success(())
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            if case .failure(let e) = r { throw e }
            return Empty()
        }
    }
}
