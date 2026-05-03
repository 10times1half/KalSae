// MARK: - 플러그인 컨텍스트

/// `KSPlugin.setup(_:)` / `teardown(_:)` 호출 시 플러그인이 받는 런타임 컨텍스트.
///
/// 이 protocol은 플러그인이 **사용할 수 있는 표면**만 정의한다:
/// - `registry` — `@KSCommand` 핸들러를 등록하는 액터
/// - `platform` — 읽기 전용 PAL 접근 (tray, menus, notifications 등)
/// - `emit(_:payload:)` — 모든 열린 창에 이벤트 브로드캐스트
public protocol KSPluginContext: Sendable {
    /// JS `invoke(name, args)` 호출을 Swift 핸들러로 연결하는 명령 레지스트리.
    var registry: KSCommandRegistry { get }

    /// 플랫폼 추상화 계층 — 현재 플랫폼의 백엔드를 노출한다.
    /// 읽기/사용만 허용된다; PAL 확장은 추후 별도 protocol로 분리될 예정.
    var platform: any KSPlatform { get }

    /// 모든 열린 창의 JS 프론트엔드에 이벤트를 브로드캐스트한다.
    func emit(_ event: String, payload: sending any Encodable) async throws(KSError)
}

// MARK: - 플러그인 계약

/// KalSae 플러그인 계약.
///
/// 플러그인은 별도 Swift 패키지로 배포되며, `KSApp.install(_:)`을 통해
/// 부팅 완료 후 등록된다. 이 시점에는 `registry`, `platform`, `emit` 모두
/// 사용 가능하다.
///
/// ### 네임스페이스 규칙
/// - `namespace`는 비어 있으면 안 된다.
/// - `__ks.`로 시작할 수 없다 (KalSae 내장 명령 예약 영역).
/// - 공백을 포함할 수 없다.
/// - 권장 형식: `<vendor>.<name>` (예: `"myco.analytics"`)
///
/// `setup` 내에서 등록하는 모든 `@KSCommand` 이름은 이 `namespace`로
/// 시작해야 한다. 강제 검사는 하지 않지만, 어기면 `commandAllowlist`와
/// 충돌이 발생할 수 있다.
///
/// ### 최소 구현 예
/// ```swift
/// public struct GreeterPlugin: KSPlugin {
///     public static let namespace = "myco.greeter"
///     public init() {}
///
///     public func setup(_ ctx: any KSPluginContext) async throws(KSError) {
///         await _ksRegister_greet(into: ctx.registry)
///     }
/// }
///
/// @KSCommand("myco.greeter.greet")
/// func greet(name: String) -> String { "Hi, \(name)!" }
/// ```
public protocol KSPlugin: Sendable {
    /// 플러그인의 명령 네임스페이스 prefix.
    /// 빈 문자열, 공백 포함, `__ks.` prefix는 금지된다.
    static var namespace: String { get }

    /// 부팅 완료 후 1회 호출된다. `registry`에 명령을 등록하거나
    /// `platform`에 접근해 PAL을 읽는다.
    func setup(_ ctx: any KSPluginContext) async throws(KSError)

    /// 앱 종료 직전 1회 호출된다. 리소스 해제, 이벤트 구독 취소 등에 사용한다.
    /// 기본 구현은 no-op이므로 필요 없으면 생략해도 된다.
    func teardown(_ ctx: any KSPluginContext) async
}

extension KSPlugin {
    public func teardown(_ ctx: any KSPluginContext) async {}
}

// MARK: - 네임스페이스 검증

/// 플러그인 네임스페이스 문자열이 KalSae 규칙을 만족하는지 검사한다.
///
/// 위반 시 `KSError(code: .configInvalid, ...)` 를 throw한다.
/// `KSApp.install(_:)`이 내부적으로 호출한다.
public func ksValidatePluginNamespace(_ namespace: String) throws(KSError) {
    guard !namespace.isEmpty else {
        throw KSError.configInvalid("plugin namespace must not be empty")
    }
    guard !namespace.contains(" ") else {
        throw KSError.configInvalid(
            "plugin namespace '\(namespace)' must not contain spaces")
    }
    guard !namespace.hasPrefix("__ks.") else {
        throw KSError.configInvalid(
            "plugin namespace '\(namespace)' must not start with '__ks.' (reserved)")
    }
}
