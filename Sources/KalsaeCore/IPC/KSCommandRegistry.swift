/// `@KSCommand`으로 노출된 함수들의 스레드 안전 레지스트리.
///
/// `@KSCommand` 매크로는 `register(into:)` 호출을 생성해 타입 지워진
/// 핸들러를 여기에 추가한다. 런타임에 IPC 파이프라인은 invoke 메시지를
/// 핸들러로 해석하고, 인자를 디코딩하며, 명령을 실행하고, 결과(또는
/// `KSError`)를 인코딩해 반환한다.
public import Foundation

public actor KSCommandRegistry {
    public typealias Handler = @Sendable (Data) async -> Result<Data, KSError>

    private var handlers: [String: Handler] = [:]
    private var allowlist: Set<String>? = nil
    private var policyEvaluator: KSPolicyEvaluator? = nil
    private var metadata: [String: KSCommandMetadata] = [:]
    /// 내장 (`__ks.*`) 명령처럼 `commandAllowlist` 검사를 우회해야 하는 핸들러
    /// 이름의 집합. security scope / rate limit / policy evaluator 는 정상 적용된다.
    private var internalNames: Set<String> = []

    // MARK: - Token-bucket rate limiter

    /// 토큰 버킷 상태. 속도 제한이 비활성화되면 nil.
    private var rateLimit: KSCommandRateLimit? = nil
    private var tokens: Double = 0
    private var lastRefillTime: ContinuousClock.Instant = .now

    public init() {}

    /// 토큰 버킷 속도 제한기를 구성한다. 앱 부팅 중 한 번 호출한다
    /// (또는 속도 제한을 비활성화하려면 호출하지 않는다).
    public func setRateLimit(_ limit: KSCommandRateLimit?) {
        rateLimit = limit
        if let limit {
            tokens = Double(limit.burst)
        }
        lastRefillTime = .now
    }

    /// 호출이 설정된 속도 이내이거나 속도 제한이 비활성화된 경우
    /// `true`를 반환하고 토큰 하나를 차감한다.
    private func consumeToken() -> Bool {
        guard let limit = rateLimit else { return true }
        let now = ContinuousClock.now
        let elapsed = lastRefillTime.duration(to: now)
        let seconds =
            Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) * 1e-18
        tokens = min(Double(limit.burst), tokens + seconds * Double(limit.rate))
        lastRefillTime = now
        if tokens >= 1.0 {
            tokens -= 1.0
            return true
        }
        return false
    }

    /// 명령 허용 목록을 설정한다. `nil`이면 모든 등록된 명령을 호출할 수 있다.
    /// 설정되면 이 집합의 이름만 호출 가능하다 — 다른 호출은
    /// `KSError.commandNotAllowed`를 반환한다.
    public func setAllowlist(_ names: [String]?) {
        allowlist = names.map(Set.init)
    }

    /// Tauri 스타일 capability/permission 정책 평가기를 설정한다.
    /// `nil`이면 capability 계층은 비활성화되고 기존 `allowlist`/레거시
    /// 정책만 적용된다 (기본값, 완전 하위 호환).
    public func setPolicyEvaluator(_ evaluator: KSPolicyEvaluator?) {
        policyEvaluator = evaluator
    }

    /// `name`에 대한 핸들러를 등록(또는 교체)한다.
    public func register(_ name: String, handler: @escaping Handler) {
        handlers[name] = handler
    }

    /// 내장(`__ks.*`) 명령용 등록 경로. 일반 `register` 와 동일하지만
    /// 해당 이름을 internal 집합에 추가해 `commandAllowlist` 검사를 우회한다.
    /// 보안 scope / rate limit / policy evaluator 는 그대로 적용된다.
    public func registerInternal(_ name: String, handler: @escaping Handler) {
        handlers[name] = handler
        internalNames.insert(name)
    }

    /// `@KSCommand(permission:)` 매크로가 호출하는 정적 메타데이터 설정자.
    /// 런타임 동작에는 영향을 주지 않으며 (capability 게이팅은
    /// `KSPolicyEvaluator`가 수행), 도구(검증기/바인딩 생성기)에서
    /// 내성(introspection)할 수 있도록 보관한다.
    public func setMetadata(_ name: String, permission: String?) {
        if let permission, !permission.isEmpty {
            metadata[name] = KSCommandMetadata(permission: permission)
        } else {
            metadata.removeValue(forKey: name)
        }
    }

    /// 지정된 명령에 부착된 메타데이터를 반환한다 (없으면 nil).
    public func metadata(for name: String) -> KSCommandMetadata? {
        metadata[name]
    }

    /// 등록된 모든 메타데이터의 스냅샷.
    public func metadataSnapshot() -> [String: KSCommandMetadata] {
        metadata
    }

    /// 핸들러를 제거한다.
    public func unregister(_ name: String) {
        handlers.removeValue(forKey: name)
        internalNames.remove(name)
    }

    /// 등록된 모든 명령의 이름을 반환한다.
    public func registered() -> [String] {
        Array(handlers.keys).sorted()
    }

    /// invoke를 디스패치한다. 직렬화된 페이로드 또는 호출 실패 시
    /// JSON으로 인코딩된 `KSError`를 반환한다.
    public func dispatch(name: String, args: Data) async -> Result<Data, KSError> {
        // 면제 프리픽스(`__ks.` 등)에 해당하는 명령은 토큰을 소비하지 않는다
        // (RFC-005 §4.7). 내장 명령이 사용자 명령의 토큰을 소진하는 것을 방지.
        let isExempt: Bool = {
            guard let limit = rateLimit else { return true }
            return limit.exemptPrefixes.contains(where: { name.hasPrefix($0) })
        }()
        if !isExempt && !consumeToken() {
            return .failure(.rateLimited(name))
        }
        // 내장 명령(`registerInternal` 로 등록)은 사용자 정의 allowlist 검사를 우회한다.
        // 보안 scope / policy evaluator 는 아래에서 그대로 평가된다.
        if !internalNames.contains(name), let allowlist, !allowlist.contains(name) {
            return .failure(.commandNotAllowed(name))
        }
        if let evaluator = policyEvaluator {
            let decision = evaluator.evaluate(
                command: name,
                windowLabel: KSInvocationContext.windowLabel,
                origin: KSInvocationContext.origin)
            if case .deny(let reason) = decision {
                return .failure(
                    .permissionDenied(
                        command: name,
                        reason: reason.message,
                        capability: reason.capabilityIdentifier))
            }
        }
        guard let handler = handlers[name] else {
            return .failure(.commandNotFound(name))
        }
        return await KSInvocationContext.$commandName.withValue(name) {
            await handler(args)
        }
    }
}
