#if os(Android)
    import KalsaeCore
    import Foundation

    // MARK: - 공유 런타임 상태

    // nonisolated(unsafe): 시작 시 한 번 설정됨. 이후는 읽기 전용.
    // 시작 후 모든 접근은 _startupLock으로 보호됨.
    nonisolated(unsafe) private var _sharedHost: KSAndroidDemoHost? = nil
    nonisolated(unsafe) private var _sharedPlatform: KSAndroidPlatform? = nil
    private let _startupLock = NSLock()

    // MARK: - 훅 등록 (KS_android_startup 전에 호출)

    /// Kalsae가 JavaScript를 평가하는 데 사용할 C 함수를 등록한다.
    ///
    /// Kotlin 사용법 (`MainActivity.onCreate`에서, `KS_android_startup` 전에):
    /// ```kotlin
    /// KalsaeJNI.registerEvaluateJs { js -> webView.evaluateJavascript(js, null) }
    /// ```
    /// Kotlin 헬퍼는 `Samples/KalsaeAndroidSample/`에 있다.
    @_cdecl("KS_android_register_evaluate_js")
    public func KS_android_register_evaluate_js(
        _ fn: @convention(c) (UnsafePointer<CChar>) -> Void
    ) {
        _hooksLock.withLock { _jniEvaluateJS = fn }
    }

    /// Kalsae가 WebView를 타색하는 데 사용할 C 함수를 등록한다.
    ///
    /// Kotlin 사용법:
    /// ```kotlin
    /// KalsaeJNI.registerLoadUrl { url -> webView.loadUrl(url) }
    /// ```
    @_cdecl("KS_android_register_load_url")
    public func KS_android_register_load_url(
        _ fn: @convention(c) (UnsafePointer<CChar>) -> Void
    ) {
        _hooksLock.withLock { _jniLoadURL = fn }
    }

    // MARK: - 시작

    /// 기본 단일 윈도우 설정으로 Kalsae Android 런타임을 초기화한다.
    ///
    /// 훅 콜백을 등록한 후 `Activity.onCreate()`에서 호출한다.
    /// 성공 시 0을, 오류 시 비제로 값을 반환한다.
    ///
    /// 멱등성 — 여러 번 호출해도 안전하다; 이후 호출은 no-op이다.
    @_cdecl("KS_android_startup")
    public func KS_android_startup() -> Int32 {
        _startupLock.lock()
        defer { _startupLock.unlock() }
        guard _sharedHost == nil else { return 0 }

        let platform = KSAndroidPlatform()
        let windowConfig = KSWindowConfig(label: "main", title: "Kalsae App")
        do {
            let host = try KSAndroidDemoHost(
                windowConfig: windowConfig,
                registry: platform.commandRegistry)
            _sharedPlatform = platform
            _sharedHost = host
            Task { @MainActor in
                wireJNIHooks(into: host.webViewHost)
            }
            return 0
        } catch {
            KSLog.logger("jni").error("KS_android_startup: host init failed")
            return -1
        }
    }

    // MARK: - 탐색

    /// WebView를 `url`로 탐색한다.
    ///
    /// Activity의 WebView가 아직 연결되지 않은 경우 URL을 대기열에 저장하고
    /// `KS_android_on_view_created()`가 호출된 후 플러시한다.
    @_cdecl("KS_android_navigate")
    public func KS_android_navigate(_ url: UnsafePointer<CChar>) {
        let urlStr = String(cString: url)
        Task { @MainActor in
            try? _startupLock.withLock({ _sharedHost })?.start(url: urlStr, devtools: false)
        }
    }

    /// Activity의 WebView가 준비되었음을 알린다. 대기중인 URL을 플러시한다.
    ///
    /// `Activity.onViewCreated` (또는 `WebView.setWebViewClient` 후)에서 호출한다.
    @_cdecl("KS_android_on_view_created")
    public func KS_android_on_view_created() {
        Task { @MainActor in
            _startupLock.withLock({ _sharedHost })?.webViewHost.flushPendingURL()
        }
    }

    // MARK: - 도큐먼트 시작 스크립트

    /// `WebViewCompat.addDocumentStartJavaScript`를 통해 주입할
    /// 복합 도큐먼트 시작 JavaScript를 반환한다.
    ///
    /// **Android 메인 스레드에서 호출해야 한다** (`KS_android_startup` 이후).
    /// 호출자가 반환된 C 문자열을 소유하며 `KS_android_free_string`으로
    /// 해제해야 한다.
    @_cdecl("KS_android_document_start_script")
    public func KS_android_document_start_script() -> UnsafeMutablePointer<CChar>? {
        guard let host = _startupLock.withLock({ _sharedHost }) else { return nil }
        // MainActor.assumeIsolated는 이 함수가 Android 메인 (UI) 스레드를
        // 요구한다고 문서화되어 있어 유효하다.
        let script = MainActor.assumeIsolated { host.webViewHost.documentStartScript() }
        return strdup(script)
    }

    /// `KS_android_*` 함수가 반환한 C 문자열을 해제한다.
    @_cdecl("KS_android_free_string")
    public func KS_android_free_string(_ ptr: UnsafeMutablePointer<CChar>?) {
        free(ptr)
    }

    // MARK: - 인바운드 메시지

    /// JS에서 Swift로 JSON 메시지를 전달한다.
    ///
    /// Kotlin `WebAppInterface`의 `@JavascriptInterface` 메서드에서 호출한다:
    /// ```kotlin
    /// @JavascriptInterface
    /// fun postMessage(json: String) = KalsaeJNI.onInboundMessage(json)
    /// ```
    /// 스레드 안전 — Android는 `@JavascriptInterface` 호출을 메인 스레드와
    /// 다른 스레드에서 전달할 수 있다.
    @_cdecl("KS_android_on_inbound_message")
    public func KS_android_on_inbound_message(_ json: UnsafePointer<CChar>) {
        let str = String(cString: json)
        _startupLock.withLock({ _sharedHost })?.webViewHost.onInboundMessage(str)
    }

    // MARK: - Activity lifecycle

    /// Call from `Activity.onResume`.
    @_cdecl("KS_android_on_resume")
    public func KS_android_on_resume() {
        Task { @MainActor in
            _startupLock.withLock({ _sharedHost })?.notifyResume()
        }
    }

    /// Call from `Activity.onPause`.
    @_cdecl("KS_android_on_pause")
    public func KS_android_on_pause() {
        Task { @MainActor in
            _startupLock.withLock({ _sharedHost })?.notifySuspend()
        }
    }
#endif
