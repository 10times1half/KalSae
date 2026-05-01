#if os(Android)
public import KalsaeCore
public import Foundation

/// Android 플랫폼(API 26+)에서 사용하는 단일 윈도우 호스트.
/// `KSApp`이 부팅 로직을 공유할 수 있도록 `KSiOSDemoHost`과 유사하게 설계된다.
///
/// 실제 `android.webkit.WebView` 및 Activity 라이프사이클 콜백은 외부
/// Kotlin 샘플에 있으며 이 Swift 패키지에는 포함되지 않는다.
/// 외부 샘플은 `webViewHost`를 얻어 훅을 연결한 후 `onViewCreated`에서
/// `flushPendingURL()`을 호출한다.
@MainActor
public final class KSAndroidDemoHost {
    public let registry: KSCommandRegistry

    /// JNI 훅 연결을 위해 `KS_android_register_evaluate_js` /
    /// `KS_android_register_load_url` 를 통해 노출됨 (`KSAndroidJNI.swift` 참조).
    /// Kotlin 측은 `Samples/KalsaeAndroidSample/`에 예시가 있다.
    public let webViewHost: KSAndroidWebViewHost
    private let bridge: KSAndroidBridge

    private let windowConfig: KSWindowConfig
    private var _pendingDevtools: Bool = false

    private var _onSuspend: (@MainActor () -> Void)?
    private var _onResume: (@MainActor () -> Void)?

    public init(windowConfig: KSWindowConfig,
                registry: KSCommandRegistry) throws(KSError) {
        self.registry = registry
        self.windowConfig = windowConfig
        self.webViewHost = KSAndroidWebViewHost()
        self.bridge = KSAndroidBridge(host: webViewHost, registry: registry)
        try self.bridge.install()
    }

    public func addDocumentCreatedScript(_ script: String) throws(KSError) {
        try webViewHost.addDocumentCreatedScript(script)
    }

    public func setAssetRoot(_ root: URL) throws(KSError) {
        try webViewHost.setAssetRoot(root)
    }

    /// 시작 URL을 저장한다; 실제 탐색은 Activity가
    /// `webViewHost.onLoadURL`를 연결하고 `webViewHost.flushPendingURL()`를
    /// 호출할 때 실행된다.
    public func start(url: String, devtools: Bool) throws(KSError) {
        _pendingDevtools = devtools
        try webViewHost.navigate(url: url)
    }

    public func emit(_ event: String, payload: any Encodable) throws(KSError) {
        try bridge.emit(event: event, payload: payload)
    }

    /// Android 프로세스는 Activity 라이프사이클에 의해 유지된다;
    /// 이 스터브는 즉시 0을 반환한다. Activity가 자체 라이프사이클를 관리한다.
    public func runMessageLoop() -> Int32 {
        0
    }

    nonisolated public func postJob(_ block: @escaping @MainActor () -> Void) {
        Task { @MainActor in block() }
    }

    nonisolated public func requestQuit() {
        // Android Activity 종료는 Activity 자체에서 처리된다.
    }

    public func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?) { _ = cb }

    public func setOnSuspend(_ cb: (@MainActor () -> Void)?) {
        _onSuspend = cb
    }

    public func setOnResume(_ cb: (@MainActor () -> Void)?) {
        _onResume = cb
    }

    /// Kotlin Activity가 `onPause`에서 호출한다.
    public func notifySuspend() { _onSuspend?() }
    /// Kotlin Activity가 `onResume`에서 호출한다.
    public func notifyResume() { _onResume?() }

    public func setWindowStateSaveSink(
        _ sink: (@MainActor (KSPersistedWindowState) -> Void)?
    ) {
        _ = sink
    }
}
#endif

