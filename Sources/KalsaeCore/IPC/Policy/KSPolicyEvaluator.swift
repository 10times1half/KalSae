import Foundation
internal import Logging

/// IPC 디스패치 직전에 호출되는 정책 평가 엔진.
///
/// `KSCapabilitiesConfig`(권한 카탈로그 + capability 정책)와 현재 플랫폼
/// 식별자를 받아, `(windowLabel, commandName)` 쌍에 대해 허용/거부 결정을
/// 내린다.
///
/// 평가 순서:
/// 1. 윈도우 라벨에 매칭되고 현재 플랫폼에 활성화된 capability를 모두 수집.
/// 2. 각 capability의 권한 목록을 카탈로그에서 해결.
/// 3. **deny 우선** — 어떤 권한이라도 명시적 `commandsDeny`를 보유하면 즉시 거부.
/// 4. 어느 권한이라도 `commandsAllow`로 매칭하면 허용.
/// 5. 어디에도 매칭되지 않으면 거부.
///
/// 결정은 `(windowLabel, commandName)` 키 LRU 캐시(최대 512개)에 보관되어
/// 동일 호출 반복에서 재평가를 생략한다.
public final class KSPolicyEvaluator: @unchecked Sendable {

    /// 현재 플랫폼 식별자 (`"windows"`, `"macOS"`, `"linux"`, `"iOS"`, `"android"`).
    public let platform: String

    private let config: KSCapabilitiesConfig
    private let permissionsByID: [String: KSPermission]
    private let logger: Logger

    private let cacheLock = NSLock()
    private var cache: [CacheKey: KSPolicyDecision] = [:]
    private var cacheOrder: [CacheKey] = []
    private let cacheLimit = 512

    private struct CacheKey: Hashable, Sendable {
        let windowLabel: String
        let commandName: String
        let origin: String
    }

    public init(config: KSCapabilitiesConfig, platform: String) {
        self.config = config
        self.platform = platform
        var byID: [String: KSPermission] = [:]
        for p in config.permissions {
            byID[p.identifier] = p
        }
        self.permissionsByID = byID
        self.logger = Logger(label: "kalsae.ipc.policy")
    }

    /// 평가의 진입점. evaluator가 비활성이거나 capability가 비어 있을 때는
    /// `nil`을 반환해 호출측이 레거시 경로(allowlist 등)로 폴백하게 한다.
    public func evaluate(
        command: String, windowLabel: String?, origin: String? = nil
    ) -> KSPolicyDecision {
        let label = windowLabel ?? ""
        let originKey = origin ?? ""
        let key = CacheKey(windowLabel: label, commandName: command, origin: originKey)

        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let decision = compute(command: command, windowLabel: label, origin: origin)

        cacheLock.lock()
        cache[key] = decision
        cacheOrder.append(key)
        if cacheOrder.count > cacheLimit {
            let evict = cacheOrder.removeFirst()
            cache.removeValue(forKey: evict)
        }
        cacheLock.unlock()

        return decision
    }

    /// 캐시를 비운다. capabilities를 런타임에 교체하는 경우 호출.
    public func invalidateCache() {
        cacheLock.lock()
        cache.removeAll(keepingCapacity: true)
        cacheOrder.removeAll(keepingCapacity: true)
        cacheLock.unlock()
    }

    private func compute(
        command: String, windowLabel: String, origin: String?
    ) -> KSPolicyDecision {
        // 1. 현재 윈도우/플랫폼/origin에 매칭되는 capability 수집.
        var matched: [KSCapability] = []
        for cap in config.capabilities {
            guard cap.matches(platform: platform) else { continue }
            guard cap.matches(windowLabel: windowLabel) else { continue }
            guard cap.matches(origin: origin) else { continue }
            matched.append(cap)
        }
        guard !matched.isEmpty else {
            return .deny(reason: .noMatchingCapability)
        }

        // 2~4. deny 우선 / allow 평가.
        var firstUnknown: (capability: String, permission: String)? = nil
        var allowingCapability: String? = nil

        for cap in matched {
            for permID in cap.permissions {
                guard let perm = permissionsByID[permID] else {
                    if firstUnknown == nil {
                        firstUnknown = (cap.identifier, permID)
                    }
                    continue
                }
                switch perm.decision(for: command) {
                case .deny:
                    return .deny(
                        reason: .explicitDeny(
                            capability: cap.identifier,
                            permission: perm.identifier))
                case .allow:
                    if allowingCapability == nil {
                        allowingCapability = cap.identifier
                    }
                case .unspecified:
                    continue
                }
            }
        }

        if let cap = allowingCapability {
            return .allow(capability: cap)
        }
        if let unk = firstUnknown {
            return .deny(reason: .unknownPermission(capability: unk.capability, permission: unk.permission))
        }
        return .deny(reason: .notInAllowlist(capability: matched[0].identifier))
    }
}

extension KSPolicyEvaluator {
    /// 현재 호스트 OS 식별자 (`KSCapability.platforms` 값과 일치).
    public static var hostPlatform: String {
        #if os(Windows)
            return "windows"
        #elseif os(macOS)
            return "macOS"
        #elseif os(Linux)
            return "linux"
        #elseif os(iOS)
            return "iOS"
        #elseif os(Android)
            return "android"
        #else
            return "unknown"
        #endif
    }
}
