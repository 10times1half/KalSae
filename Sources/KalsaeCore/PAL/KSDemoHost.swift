public import Foundation

/// 모든 플랫폼 DemoHost가 구현해야 할 기본 프로토콜.
///
/// `KSApp`과 플랫폼별 호스트 구현(macOS, Windows, Linux, iOS, Android)
/// 사이의 명시적 계약을 정의한다.
///
/// **기본 메서드:**
/// - 초기화: `init(windowConfig:registry:)`
/// - 부팅: `start(url:devtools:)`, `runMessageLoop()`
/// - 통신: `emit(_:payload:)`, `postJob(_:)`
/// - UI: `reload()`, `requestQuit()`, `setOnBeforeClose(_:)` 등
/// - 상태: `setWindowStateSaveSink(_:)`, `addDocumentCreatedScript(_:)`
///
/// **플랫폼별 확장 프로토콜:**
/// - `KSDemoHostWithAssetRoot` — macOS/Linux/iOS/Android에서 `setAssetRoot(_:)` 제공
/// - `KSDemoHostWithSecurity` — 보안 설정 관련 메서드 제공
@MainActor
public protocol KSDemoHost: AnyObject, Sendable {
    /// 명령 레지스트리. 기본 명령과 사용자 정의 명령을 관리한다.
    var registry: KSCommandRegistry { get }

    /// 이 호스트의 IPC 브리지. JS 프론트엔드와 Swift IPC 코어를 연결한다.
    /// 모든 플랫폼 DemoHost는 정확히 하나의 브리지를 갖는다.
    var bridge: any KSBridge { get }

    /// 이 호스트의 주 윈도우 핸들 (선택적).
    /// 다중 윈도우 시스템에서 주 창을 구분하기 위해 사용된다.
    var mainHandle: KSWindowHandle? { get }

    /// URL을 로드하고 DevTools 상태를 설정한 후 메시지 루프를 시작한다.
    func start(url: String, devtools: Bool) throws(KSError)

    /// JS 측으로 이벤트를 발생시킨다.
    func emit(_ event: String, payload: any Encodable) throws(KSError)

    /// 현재 페이지를 새로고친다.
    func reload()

    /// 메시지 루프를 시작하고 종료 코드를 반환한다.
    /// 일반적으로 플랫폼 메인 이벤트 루프 이후에 호출된다.
    func runMessageLoop() -> Int32

    /// 메인 스레드에서 비동기로 작업을 큐에 넣는다.
    /// 이 메서드는 nonisolated이어야 하므로 백그라운드 스레드에서도 호출 가능하다.
    nonisolated func postJob(_ block: @escaping @MainActor () -> Void)

    /// 우아한 종료를 요청한다.
    nonisolated func requestQuit()

    /// 창 닫기 이전에 호출될 콜백. `true`를 반환하면 종료가 취소된다.
    func setOnBeforeClose(_ cb: (@MainActor () -> Bool)?)

    /// 앱이 백그라운드로 전환될 때 호출될 콜백 (iOS/Android).
    func setOnSuspend(_ cb: (@MainActor () -> Void)?)

    /// 앱이 포그라운드로 복귀할 때 호출될 콜백 (iOS/Android).
    func setOnResume(_ cb: (@MainActor () -> Void)?)

    /// 창 크기/위치 변경 시 호출될 콜백. 상태 영속화에 사용된다.
    func setWindowStateSaveSink(_ sink: (@MainActor (KSPersistedWindowState) -> Void)?)

    /// DOM이 준비되었을 때 주입될 스크립트를 추가한다. (예: CSP meta 태그)
    func addDocumentCreatedScript(_ script: String) throws(KSError)
}

/// 자산 루트 설정을 지원하는 플랫폼 (macOS, Linux, iOS, Android).
public protocol KSDemoHostWithAssetRoot: KSDemoHost {
    /// 가상 호스트가 제공할 자산의 로컬 디렉터리를 설정한다.
    func setAssetRoot(_ root: URL) throws(KSError)
}

/// 보안 설정을 지원하는 플랫폼 (모든 플랫폼).
public protocol KSDemoHostWithSecurity: KSDemoHost {
    /// 우측 클릭 컨텍스트 메뉴 활성화/비활성화.
    func setDefaultContextMenusEnabled(_ enabled: Bool)

    /// 외부 파일 드래그 앤 드롭 활성화/비활성화.
    func setAllowExternalDrop(_ allow: Bool)

    /// 보안 핸들러 설치 (팝업 차단, 외부 URL 라우팅 등).
    func installSecurityHandlers(
        allowPopups: Bool,
        openExternal: @escaping (String) -> Void
    ) throws(KSError)
}

/// 파일 드롭 이벤트 발생을 지원하는 플랫폼 (Windows).
public protocol KSDemoHostWithFileDropEmitter: KSDemoHost {
    /// 외부 파일 드롭 이벤트를 위한 이미터 설치.
    func installFileDropEmitter() throws(KSError)
}

/// Windows 전용: 자산 리소스 핸들러 설정.
public protocol KSDemoHostWithResourceHandler: KSDemoHost {
    /// 가상 호스트 요청에 대한 자산 리소스 핸들러를 설정한다.
    func setResourceHandler(
        resolver: KSAssetResolver,
        csp: String,
        host: String
    ) throws(KSError)
}

/// Windows 전용: 부팅 두 단계 분리.
public protocol KSDemoHostWithPreparedStart: KSDemoHost {
    /// WebView 환경 초기화. `start()` 전에 호출 가능.
    func prepare(devtools: Bool) throws(KSError)

    /// 미리 준비된 상태에서 URL을 로드한다.
    func startPrepared(url: String, devtools: Bool) throws(KSError)
}

/// Linux 전용: CSP 응답 헤더 설정.
public protocol KSDemoHostWithResponseCSP: KSDemoHost {
    /// HTTP 응답에 포함될 CSP 헤더 설정.
    func setResponseCSP(_ csp: String) throws(KSError)
}

/// 사용자 스크립트 주입을 지원하는 플랫폼 (모든 플랫폼).
///
/// `addDocumentCreatedScript`와 동일하게 "문서 생성 시 실행될 JS 문자열" 등록만
/// 수행한다. 보안 정책(origin 가드, documentEnd 폴리필, 예외 격리)은
/// `KSUserScriptWrapper`가 호스트 위에서 적용한 IIFE로 처리하므로 백엔드는
/// 단순히 등록만 하면 된다. 개별 제거는 v0.x 범위 밖이다 — Tauri v2의
/// `initialization_script`와 동일하게 부팅 시점 또는 그 이후 단방향 추가만
/// 지원한다.
public protocol KSDemoHostWithUserScripts: KSDemoHost {
    /// 래핑이 끝난 IIFE 문자열을 사용자 스크립트로 등록한다.
    /// 동일한 `id`에 대한 중복 호출 방지는 호출자(KSApp)가 책임진다.
    func addUserScript(id: String, wrappedSource: String, forMainFrameOnly: Bool) throws(KSError)
}
