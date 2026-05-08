/// IPC 명령 호출에 대한 토큰 버킷 속도 제한 정책.
///
/// 최대 `burst`번의 연속 호출은 허용되고, 그 이후에는 초당 `rate`개의 토큰으로 버킷이 채워진다.
/// JS가 Swift 측을 고빈도 호출로 과도하게 밀어붙이는 것을 막는 데 사용한다.
///
/// ```json
/// "commandRateLimit": { "rate": 100, "burst": 200 }
/// ```
import Foundation

public struct KSCommandRateLimit: Codable, Sendable, Equatable {
    /// 지속 호출 속도(초당 다시 채워지는 토큰 수).
    public var rate: Int
    /// 최대 버스트 크기(토큰 버킷 용량).
    public var burst: Int
    /// 속도 제한에서 제외할 명령 프리픽스 목록. 이 프리픽스로 시작하는
    /// 명령은 토큰을 소비하지 않는다. 기본값 `["__ks."]`은 프레임워크
    /// 내장 명령(`__ks.log`, `__ks.window.*` 등)을 면제해 사용자 명령의
    /// 토큰을 소진하지 않게 한다 (RFC-005 §4.7).
    public var exemptPrefixes: [String]

    public init(
        rate: Int = 100,
        burst: Int = 200,
        exemptPrefixes: [String] = ["__ks."]
    ) {
        self.rate = max(1, rate)
        self.burst = max(1, burst)
        self.exemptPrefixes = exemptPrefixes
    }

    private enum CodingKeys: String, CodingKey {
        case rate, burst, exemptPrefixes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.rate = max(1, try c.decode(Int.self, forKey: .rate))
        self.burst = max(1, try c.decode(Int.self, forKey: .burst))
        self.exemptPrefixes =
            (try? c.decode([String].self, forKey: .exemptPrefixes)) ?? ["__ks."]
    }
}
