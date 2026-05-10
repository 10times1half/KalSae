#if os(macOS)
    internal import AppKit
    internal import WebKit
    internal import Logging
    public import KalsaeCore
    public import Foundation

    @MainActor
    public final class WKWebViewHost: KSWebViewBackend {
        internal let webView: WKWebView
        private let userContentController: WKUserContentController
        private let log: Logger = KSLog.logger("platform.mac.webview")
        private var inbound: ((String) -> Void)?
        private var ipcHandler: (@Sendable (KSIPCMessage) async -> Void)?
        private let messageHandler: KSScriptMessageHandler
        private let schemeHandler: KSMacSchemeHandler
        private var closeInterceptorEnabled = false
        private var zoomFactor: Double = 1.0
        nonisolated(unsafe) private static let _sharedEncoder = JSONEncoder()

        public convenience init(label: String) {
            self.init(label: label, options: nil)
        }

        public init(label: String, options: KSWebViewOptions?) {
            let ucc = WKUserContentController()
            self.userContentController = ucc
            self.messageHandler = KSScriptMessageHandler()
            self.schemeHandler = KSMacSchemeHandler()

            let config = WKWebViewConfiguration()
            config.userContentController = ucc
            config.setURLSchemeHandler(schemeHandler, forURLScheme: "ks")
            if #available(macOS 13.3, *) {
                config.preferences.isElementFullscreenEnabled = true
            }

            // Phase A2/D2: cross-platform preferences + macOS escape hatches.
            // 모든 매핑 결과는 capability 레지스트리에 기록되어 `__ks.webview.capabilities()` 로
            // 조회 가능하다.
            let log = KSLog.logger("platform.mac.webview")
            let caps = WKWebViewHost.applyConfiguration(config, options: options, log: log)

            // userDataPath: 검증 통과 시 macOS 14+ `WKWebsiteDataStore(forIdentifier:)` 분리.
            if let raw = options?.userDataPath {
                do {
                    let resolved = try KSUserDataPathValidator.validate(raw)
                    if #available(macOS 14, *) {
                        // 안정 식별자 도출 — 같은 경로 = 같은 데이터 스토어.
                        let uuid = WKWebViewHost.uuidForPath(resolved)
                        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: uuid)
                        caps.record("userDataPath", .applied)
                    } else {
                        log.warning("userDataPath requires macOS 14+; ignored")
                        caps.record("userDataPath", .unsupported)
                    }
                } catch {
                    log.warning("userDataPath rejected: \(error.message); falling back to default store")
                    caps.record("userDataPath", .error(error.message))
                }
            }

            let userScript = WKUserScript(
                source: KSRuntimeJS.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            ucc.addUserScript(userScript)

            self.webView = WKWebView(frame: .zero, configuration: config)
            self.webView.autoresizingMask = [.width, .height]

            // post-creation 토글 (`isInspectable` 등).
            WKWebViewHost.applyPostCreate(webView: self.webView, options: options, log: log, caps: caps)

            self.capabilities = caps

            messageHandler.onMessage = { [weak self] text in
                self?.inbound?(text)
            }
            ucc.add(messageHandler, name: "ks")

            log.info("WKWebView created (label=\(label))")
        }

        /// 적용된 preference / 플랫폼 옵션의 capability 보고.
        /// `__ks.webview.capabilities()` 명령에서 노출된다.
        public let capabilities: KSWebViewCapabilityReport

        // MARK: - Configuration mapping (Phase A2 / D2)

        nonisolated private static func applyConfiguration(
            _ config: WKWebViewConfiguration,
            options: KSWebViewOptions?,
            log: Logger
        ) -> KSWebViewCapabilityReport {
            let caps = KSWebViewCapabilityReport()

            // preferences (cross-platform)
            if let p = options?.preferences {
                if let js = p.javaScriptEnabled {
                    config.defaultWebpagePreferences.allowsContentJavaScript = js
                    if !js {
                        log.warning("javaScriptEnabled=false: IPC will not function")
                    }
                    caps.record("javaScriptEnabled", .applied)
                }
                if let warn = p.fraudulentWebsiteWarning {
                    config.preferences.isFraudulentWebsiteWarningEnabled = warn
                    caps.record("fraudulentWebsiteWarning", .applied)
                }
                if let inline = p.allowsInlineMediaPlayback {
                    // `WKWebViewConfiguration.allowsInlineMediaPlayback` 은
                    // iOS / iPadOS / Mac Catalyst 전용이다. macOS 네이티브
                    // WebKit은 비디오를 항상 인라인 재생하므로 토글 자체가
                    // 존재하지 않는다.
                    #if targetEnvironment(macCatalyst)
                        config.allowsInlineMediaPlayback = inline
                        caps.record("allowsInlineMediaPlayback", .applied)
                    #else
                        _ = inline
                        caps.record("allowsInlineMediaPlayback", .unsupported)
                    #endif
                }
                if let autoplay = p.mediaAutoplay {
                    let types: WKAudiovisualMediaTypes = {
                        switch autoplay {
                        case .never: return .all
                        case .userGesture: return [.video, .audio]
                        case .always: return []
                        }
                    }()
                    config.mediaTypesRequiringUserActionForPlayback = types
                    caps.record("mediaAutoplay", .applied)
                }
                // 명시적으로 macOS에서 의미 없는 토글들.
                if p.hardwareAcceleration != nil {
                    caps.record("hardwareAcceleration", .unsupported)
                }
                if p.smoothScrolling != nil {
                    caps.record("smoothScrolling", .unsupported)
                }
                if p.autofill != nil {
                    caps.record("autofill", .unsupported)
                }
                if let lang = p.language, !lang.isEmpty {
                    // WKWebView 자체는 언어 직접 지정 API가 없지만 Accept-Language는
                    // CFNetwork 기본 동작에 위임된다. 향후 customUserAgent에 합성할 수 있어
                    // 여기서는 unsupported로 보고만 한다.
                    caps.record("language", .unsupported)
                }
            }

            // platform.mac escape hatch
            if let m = options?.platform?.mac {
                if let limit = m.limitNavigationsToAppBoundDomains {
                    config.limitsNavigationsToAppBoundDomains = limit
                    caps.record("platform.mac.limitNavigationsToAppBoundDomains", .applied)
                }
                if let suppress = m.suppressIncrementalRendering {
                    config.suppressesIncrementalRendering = suppress
                    caps.record("platform.mac.suppressIncrementalRendering", .applied)
                }
                if let mode = m.preferredContentMode {
                    let wk: WKWebpagePreferences.ContentMode = {
                        switch mode {
                        case .recommended: return .recommended
                        case .mobile: return .mobile
                        case .desktop: return .desktop
                        }
                    }()
                    config.defaultWebpagePreferences.preferredContentMode = wk
                    caps.record("platform.mac.preferredContentMode", .applied)
                }
                if m.shareProcessPool == true {
                    config.processPool = SharedProcessPool.shared
                    caps.record("platform.mac.shareProcessPool", .applied)
                }
            }

            // 잘못된 플랫폼에 지정된 옵션들은 unsupported로 일괄 기록.
            if options?.platform?.windows != nil {
                caps.record("platform.windows", .unsupported)
            }
            if options?.platform?.linux != nil {
                caps.record("platform.linux", .unsupported)
            }

            return caps
        }

        nonisolated private static func applyPostCreate(
            webView: WKWebView,
            options: KSWebViewOptions?,
            log: Logger,
            caps: KSWebViewCapabilityReport
        ) {
            let prefs = options?.preferences

            // developerExtrasEnabled 자동 기본값: 디버그=true / 릴리스=false.
            let inspectable: Bool = prefs?.developerExtrasEnabled ?? KSBuildMode.isDebug
            if #available(macOS 13.3, *) {
                webView.isInspectable = inspectable
                caps.record("developerExtrasEnabled", .applied)
            } else if inspectable {
                log.warning("developerExtrasEnabled requires macOS 13.3+; ignored")
                caps.record("developerExtrasEnabled", .unsupported)
            }

            if let swipe = prefs?.swipeNavigation {
                webView.allowsBackForwardNavigationGestures = swipe
                caps.record("swipeNavigation", .applied)
            }
        }

        /// 사용자 데이터 경로 → 결정적 UUID. macOS 14+ `WKWebsiteDataStore(forIdentifier:)` 용.
        nonisolated private static func uuidForPath(_ path: String) -> UUID {
            // SHA를 못 쓰는 환경이라도 결정성만 보장되면 충분하다.
            // FNV-1a 64bit 해시를 두 번 굴려 128비트 UUID 비트를 채운다.
            func fnv1a(_ s: String, salt: UInt64) -> UInt64 {
                var hash: UInt64 = 0xcbf2_9ce4_8422_2325 ^ salt
                for byte in s.utf8 {
                    hash ^= UInt64(byte)
                    hash = hash &* 0x100_0000_01b3
                }
                return hash
            }
            let h1 = fnv1a(path, salt: 0)
            let h2 = fnv1a(path, salt: 0xdead_beef_cafe_babe)
            var bytes = [UInt8](repeating: 0, count: 16)
            for i in 0..<8 {
                bytes[i] = UInt8(truncatingIfNeeded: h1 >> (i * 8))
                bytes[i + 8] = UInt8(truncatingIfNeeded: h2 >> (i * 8))
            }
            return UUID(
                uuid: (
                    bytes[0], bytes[1], bytes[2], bytes[3],
                    bytes[4], bytes[5], bytes[6], bytes[7],
                    bytes[8], bytes[9], bytes[10], bytes[11],
                    bytes[12], bytes[13], bytes[14], bytes[15]
                ))
        }

        /// macOS 다중 창 간 공유 process pool. `platform.mac.shareProcessPool=true` 로 활성화.
        private enum SharedProcessPool {
            nonisolated(unsafe) static let shared = WKProcessPool()
        }

        // MARK: - KSWebViewBackend

        public func load(url: URL) async throws(KSError) {
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
        }

        @discardableResult
        public func evaluateJavaScript(_ source: String) async throws(KSError) -> Data? {
            do {
                return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data?, any Error>) in
                    webView.evaluateJavaScript(source) { result, error in
                        if let error {
                            cont.resume(throwing: error)
                            return
                        }
                        if let result, !(result is NSNull) {
                            if let data = try? JSONSerialization.data(withJSONObject: result, options: []) {
                                cont.resume(returning: data)
                            } else {
                                cont.resume(returning: nil)
                            }
                        } else {
                            cont.resume(returning: nil)
                        }
                    }
                }
            } catch {
                throw KSError(code: .internal, message: "evaluateJavaScript: \(error)")
            }
        }

        public func postMessage(_ message: KSIPCMessage) async throws(KSError) {
            let data: Data
            do {
                data = try Self._sharedEncoder.encode(message)
            } catch {
                throw KSError(code: .internal, message: "postMessage: \(error)")
            }
            guard let json = String(data: data, encoding: .utf8) else {
                throw KSError(code: .internal, message: "postMessage: JSON encoding failed")
            }
            try postJSON(json)
        }

        public func setMessageHandler(_ handler: @Sendable @escaping (KSIPCMessage) async -> Void) async {
            self.ipcHandler = handler
        }

        public func setContentSecurityPolicy(_ csp: String) async throws(KSError) {
            schemeHandler.csp = csp
        }

        public func setCrossOriginIsolation(_ enabled: Bool) {
            schemeHandler.crossOriginIsolation = enabled
        }

        public func openDevTools() throws(KSError) {
            if #available(macOS 13.3, *) {
                webView.isInspectable = true
                log.info("WKWebView isInspectable = true")
            } else {
                log.warning("Web Inspector requires macOS 13.3+")
            }
        }

        // MARK: - 레거시 브리지 인터페이스

        public func onMessage(_ handler: @escaping @MainActor (String) -> Void) throws(KSError) {
            self.inbound = handler
        }

        public func navigate(url: String) throws(KSError) {
            guard let u = URL(string: url) else {
                throw KSError(code: .webviewInitFailed, message: "Invalid URL: \(url)")
            }
            if u.isFileURL {
                webView.loadFileURL(u, allowingReadAccessTo: u.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: u))
            }
        }

        public func postJSON(_ json: String) throws(KSError) {
            // U+2028(Line Separator)/U+2029(Paragraph Separator)는 ECMAScript에서
            // 라인 터미네이터이므로 문자열 리터럴 내부에서 구문 오류를
            // 일으키어. JSONEncoder가 이스케이프하지 않으므로 수동 치환 (RFC-005 §4.8).
            let safe =
                json
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            let script = "window.__KS_receive(\(safe));"
            webView.evaluateJavaScript(script) { _, err in
                if let err {
                    KSLog.logger("platform.mac.webview")
                        .warning("evaluateJavaScript failed: \(err)")
                }
            }
        }

        public func setAssetRoot(_ root: URL) throws(KSError) {
            schemeHandler.resolver = KSAssetResolver(root: root)
        }

        public func addDocumentCreatedScript(_ script: String) throws(KSError) {
            let us = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(us)
        }

        // MARK: - RFC-008 §2.1~2.3 보안 핸들러

        // 보안 델리게이트들은 `webView.uiDelegate` / `navigationDelegate`가 weak
        // reference이므로 호스트가 강하게 보유한다.
        private var securityDelegate: KSMacSecurityDelegate?
        private var navigationDelegate: KSMacNavigationDelegate?
        private var contextMenuScriptInstalled = false
        private var externalDropScriptInstalled = false

        /// RFC-008 §2.1 — 우클릭 컨텍스트 메뉴 비활성화.
        ///
        /// JS 레벨에서 `oncontextmenu`를 preventDefault한다. macOS WKWebView는
        /// 페이지 컨텍스트 메뉴(우클릭) 자체를 비활성화하는 공식 API가 없어
        /// 동일 효과를 얻기 위한 표준 패턴이다. DEBUG 빌드의 Web Inspector는
        /// 별도 메뉴이므로 영향 없음.
        public func setDefaultContextMenusEnabled(_ enabled: Bool) {
            guard !enabled else { return }  // 활성화는 기본값이므로 no-op.
            if contextMenuScriptInstalled { return }
            contextMenuScriptInstalled = true
            let us = WKUserScript(
                source: KSMacSecurityScripts.disableContextMenu,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            userContentController.addUserScript(us)
        }

        /// RFC-008 §2.1 — 외부 파일 드롭 비활성화.
        ///
        /// `dataTransfer.types`가 'Files'인 경우만 preventDefault한다. 페이지
        /// 내부 드래그(텍스트/요소)에는 영향 없음.
        public func setAllowExternalDrop(_ allow: Bool) {
            guard !allow else { return }
            if externalDropScriptInstalled { return }
            externalDropScriptInstalled = true
            let us = WKUserScript(
                source: KSMacSecurityScripts.disableExternalDrop,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false)
            userContentController.addUserScript(us)
        }

        /// RFC-008 §2.3 — 팝업 차단 + 외부 URL 라우팅 + 권한 거부.
        ///
        /// Windows의 `installSecurityHandlers(allowPopups:openExternal:)` 와 동등.
        /// `allowPopups=false`이면 `window.open` / `target=_blank` 새 윈도우
        /// 요청을 차단하고 `openExternal`로 라우팅한다. 마이크/카메라 권한은
        /// 항상 거부된다.
        public func installSecurityHandlers(
            allowPopups: Bool,
            openExternal: (@MainActor (String) -> Void)?
        ) throws(KSError) {
            let sec = securityDelegate ?? KSMacSecurityDelegate()
            sec.allowPopups = allowPopups
            sec.openExternal = openExternal
            self.securityDelegate = sec
            self.webView.uiDelegate = sec

            let nav = navigationDelegate ?? KSMacNavigationDelegate()
            nav.openExternal = openExternal
            self.navigationDelegate = nav
            self.webView.navigationDelegate = nav
        }

        /// RFC-008 §2.2 — 외부 파일 드롭 이벤트를 JS로 emit.
        ///
        /// macOS에서는 WKWebView가 NSView로서 자체 드래그 처리를 한다. 본
        /// 메서드는 `setAllowExternalDrop(false)`와 함께 쓰일 때 의미가 있으나,
        /// macOS WKWebView는 NSDraggingDestination을 외부에서 가로채는 공식
        /// API가 없어 NSWindow 단위로만 가능하다. v1에서는 **best-effort 경고**로
        /// 등록만 받고 실제 emit은 다음 릴리스에서 NSWindow draggingDestination
        /// 통합으로 다룬다.
        public func installFileDropEmitter() throws(KSError) {
            log.warning(
                "macOS installFileDropEmitter() is a stub — file drop forwarding requires "
                    + "NSWindow draggingDestination integration; tracked as Phase 4 follow-up.")
        }

        // MARK: - 확장 PAL 인터페이스

        internal func setBackgroundColor(_ color: NSColor) {
            webView.setValue(false, forKey: "drawsBackground")
            webView.setValue(color, forKey: "backgroundColor")
        }

        public func setCloseInterceptor(_ enabled: Bool) {
            closeInterceptorEnabled = enabled
        }

        public var isCloseInterceptorEnabled: Bool { closeInterceptorEnabled }

        public func emitBeforeCloseEvent() {
            webView.evaluateJavaScript(
                "if(window.__KS_)window.__KS_.emit('__ks.window.beforeClose',null);"
            ) { _, _ in }
        }

        public func setZoomFactor(_ factor: Double) {
            let clamped = min(max(factor, 0.5), 5.0)
            zoomFactor = clamped
            webView.evaluateJavaScript("document.body.style.zoom = '\(clamped)'") { _, _ in }
        }

        public func getZoomFactor() -> Double {
            zoomFactor
        }

        public func showPrintUI(systemDialog: Bool) {
            let printInfo = NSPrintInfo.shared
            let printOp = NSPrintOperation(view: webView, printInfo: printInfo)
            printOp.showsPrintPanel = systemDialog
            printOp.run()
        }

        public func capturePreview(format: Int32) async throws(KSError) -> Data {
            do {
                return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, any Error>) in
                    let config = WKSnapshotConfiguration()
                    webView.takeSnapshot(with: config) { image, error in
                        if let error {
                            cont.resume(throwing: error)
                            return
                        }
                        guard let image else {
                            cont.resume(throwing: KSError(code: .internal, message: "capturePreview: nil image"))
                            return
                        }
                        let formatFileType: NSBitmapImageRep.FileType = format == 1 ? .jpeg : .png
                        let props: [NSBitmapImageRep.PropertyKey: Any] =
                            format == 1
                            ? [.compressionFactor: 0.9]
                            : [:]
                        if let data = image.representations.first as? NSBitmapImageRep {
                            if let bytes = data.representation(using: formatFileType, properties: props) {
                                cont.resume(returning: bytes)
                                return
                            }
                        }
                        if let tiff = image.tiffRepresentation,
                            let rep = NSBitmapImageRep(data: tiff),
                            let bytes = rep.representation(using: formatFileType, properties: props)
                        {
                            cont.resume(returning: bytes)
                            return
                        }
                        cont.resume(
                            throwing: KSError(
                                code: .internal,
                                message: "capturePreview: could not encode image"))
                    }
                }
            } catch {
                throw KSError(code: .internal, message: "capturePreview: \(error)")
            }
        }
    }

    // MARK: - ks:// 스킴 핸들러

    @MainActor
    internal final class KSMacSchemeHandler: NSObject, WKURLSchemeHandler {
        var resolver: KSAssetResolver?
        var csp: String = KSSecurityConfig.defaultCSP
        var crossOriginIsolation: Bool = false

        nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            MainActor.assumeIsolated { self.startTask(urlSchemeTask) }
        }

        nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

        private func startTask(_ task: any WKURLSchemeTask) {
            guard let url = task.request.url, let resolver else {
                task.didFailWithError(
                    NSError(domain: "Kalsae", code: 404, userInfo: [NSLocalizedDescriptionKey: "no resolver bound"]))
                return
            }
            do {
                let asset = try resolver.resolve(path: url.path)
                var headers: [String: String] = [
                    "Content-Type": asset.mimeType,
                    "Content-Length": String(asset.data.count),
                    "Content-Security-Policy": csp,
                    "X-Content-Type-Options": "nosniff",
                    "Referrer-Policy": "no-referrer",
                ]
                if crossOriginIsolation {
                    headers["Cross-Origin-Opener-Policy"] = "same-origin"
                    headers["Cross-Origin-Embedder-Policy"] = "require-corp"
                    headers["Cross-Origin-Resource-Policy"] = "same-origin"
                }
                guard
                    let response = HTTPURLResponse(
                        url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)
                else {
                    task.didFailWithError(NSError(domain: "Kalsae", code: 500))
                    return
                }
                task.didReceive(response)
                task.didReceive(asset.data)
                task.didFinish()
            } catch {
                task.didFailWithError(
                    NSError(
                        domain: "Kalsae", code: 404, userInfo: [NSLocalizedDescriptionKey: String(describing: error)]))
            }
        }
    }

    @MainActor
    internal final class KSScriptMessageHandler: NSObject, WKScriptMessageHandler {
        internal var onMessage: (@MainActor (String) -> Void)?

        nonisolated func userContentController(
            _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            let body = message.body
            MainActor.assumeIsolated {
                let text: String
                if let s = body as? String {
                    text = s
                } else if JSONSerialization.isValidJSONObject(body) {
                    if let data = try? JSONSerialization.data(withJSONObject: body, options: []),
                        let s = String(data: data, encoding: .utf8)
                    {
                        text = s
                    } else {
                        return
                    }
                } else {
                    return
                }
                self.onMessage?(text)
            }
        }
    }
#endif
