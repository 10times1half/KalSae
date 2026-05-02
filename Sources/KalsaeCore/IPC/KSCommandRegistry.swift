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

    /// `name`에 대한 핸들러를 등록(또는 교체)한다.
    public func register(_ name: String, handler: @escaping Handler) {
        handlers[name] = handler
    }

    /// 핸들러를 제거한다.
    public func unregister(_ name: String) {
        handlers.removeValue(forKey: name)
    }

    /// 등록된 모든 명령의 이름을 반환한다.
    public func registered() -> [String] {
        Array(handlers.keys).sorted()
    }

    /// invoke를 디스패치한다. 직렬화된 페이로드 또는 호출 실패 시
    /// JSON으로 인코딩된 `KSError`를 반환한다.
    public func dispatch(name: String, args: Data) async -> Result<Data, KSError> {
        if !consumeToken() {
            return .failure(.rateLimited(name))
        }
        if let allowlist, !allowlist.contains(name) {
            return .failure(.commandNotAllowed(name))
        }
        guard let handler = handlers[name] else {
            return .failure(.commandNotFound(name))
        }
        return await handler(args)
    }
}
