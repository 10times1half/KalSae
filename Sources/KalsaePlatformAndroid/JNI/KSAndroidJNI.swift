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

    // RFC-007 Phase 4 (scaffolding) — Dialog/Menu register entry points.
    // Kotlin host can install C function pointers here; the Swift PAL backends
    // (KSAndroidDialogBackend, KSAndroidMenuBackend) do not consume them yet
    // (the request-id ↔ continuation bridge is deferred to a future session).
    // Until consumed, current handler-injection behavior is preserved unchanged.

    /// Registers a Kotlin-side `AlertDialog` presenter. Kotlin replies via
    /// `KS_android_on_dialog_result(requestId, resultJson)` (to be added).
    @_cdecl("KS_android_register_show_alert")
    public func KS_android_register_show_alert(
        _ fn: @convention(c) (Int32, UnsafePointer<CChar>) -> Void
    ) {
        _hooksLock.withLock { _jniShowAlert = fn }
    }

    /// Registers a Kotlin-side file-open launcher (SAF).
    @_cdecl("KS_android_register_pick_file")
    public func KS_android_register_pick_file(
        _ fn: @convention(c) (Int32, UnsafePointer<CChar>) -> Void
    ) {
        _hooksLock.withLock { _jniPickFile = fn }
    }

    /// Registers a Kotlin-side file-save launcher (SAF).
    @_cdecl("KS_android_register_save_file")
    public func KS_android_register_save_file(
        _ fn: @convention(c) (Int32, UnsafePointer<CChar>) -> Void
    ) {
        _hooksLock.withLock { _jniSaveFile = fn }
    }

    /// Registers a Kotlin-side folder-select launcher (SAF).
    @_cdecl("KS_android_register_select_folder")
    public func KS_android_register_select_folder(
        _ fn: @convention(c) (Int32, UnsafePointer<CChar>) -> Void
    ) {
        _hooksLock.withLock { _jniSelectFolder = fn }
    }

    /// Registers a Kotlin-side `PopupMenu` presenter.
    @_cdecl("KS_android_register_show_context_menu")
    public func KS_android_register_show_context_menu(
        _ fn: @convention(c) (Int32, UnsafePointer<CChar>, Int32, Int32) -> Void
    ) {
        _hooksLock.withLock { _jniShowContextMenu = fn }
    }

    // MARK: - 다이얼로그 결과 콜백

    /// Kotlin 호스트가 비동기 UI 응답을 Swift 로 되돌릴 때 호출한다.
    ///
    /// 페어링 흐름: `KSAndroidDialogBackend` 가 `KSAndroidJNIRegistry.register`
    /// 로 발급한 requestId 를 `_jniShowAlert` / `_jniPickFile` 등으로 Kotlin 에
    /// 전달하면, Kotlin 은 사용자 응답을 받은 직후
    /// `KalsaeJNI.onDialogResult(requestId, resultJson)` 를 호출한다.
    ///
    /// 결과 JSON 형태 (호출자가 등록한 continuation 이 디코딩):
    /// - `openFile`     : `{"urls": ["file:///..."]}` (취소 시 빈 배열 또는 빠짐)
    /// - `saveFile`     : `{"url": "file:///..."}`   (취소 시 null 또는 빠짐)
    /// - `selectFolder` : `{"url": "file:///..."}`   (취소 시 null 또는 빠짐)
    /// - `message`      : `{"result": "ok"|"cancel"|"yes"|"no"}`
    ///
    /// 알 수 없거나 만료된 requestId 는 조용히 무시된다.
    @_cdecl("KS_android_on_dialog_result")
    public func KS_android_on_dialog_result(
        _ requestId: Int32,
        _ resultJSON: UnsafePointer<CChar>
    ) {
        let json = String(cString: resultJSON)
        KSAndroidJNIRegistry.shared.deliver(requestId, json: json)
    }

    /// `KSAndroidMenuBackend` 가 발급한 컨텍스트 메뉴 요청에 대해 Kotlin 호스트
    /// 가 결과를 되돌릴 때 호출한다. 사용자가 PopupMenu 의 항목을 선택하면
    /// `selectedIndex` 는 평면화된 액션 목록의 인덱스(0-based)이고, 취소되었
    /// 거나 영역 밖을 탭한 경우 `-1` 을 전달한다.
    ///
    /// Kotlin 호출 예:
    /// ```kotlin
    /// KalsaeJNI.onContextMenuResult(requestId, popupMenuSelectedIndex)
    /// ```
    ///
    /// 내부 구현 노트: 다이얼로그와 같은 `KSAndroidJNIRegistry` 풀을 재사용
    /// 하기 위해 `{"selectedIndex": N}` 형식의 JSON 으로 어댑팅한다.
    @_cdecl("KS_android_on_context_menu_result")
    public func KS_android_on_context_menu_result(
        _ requestId: Int32,
        _ selectedIndex: Int32
    ) {
        let json = "{\"selectedIndex\":\(selectedIndex)}"
        KSAndroidJNIRegistry.shared.deliver(requestId, json: json)
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
            // Kotlin 측 register* 진입점으로 등록된 훅이 있으면 다이얼로그/
            // 메뉴 백엔드의 기본 핸들러가 자동으로 그쪽을 호출하도록 위임한다.
            // 등록된 훅이 없으면 다이얼로그 백엔드는 `unsupportedPlatform` 을
            // throw 하고, 메뉴 백엔드는 조용히 종료된다(default-deny).
            platform.installJNIDialogDefaults()
            platform.installJNIMenuDefaults()
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
