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

    public init(rate: Int = 100, burst: Int = 200) {
        self.rate = max(1, rate)
        self.burst = max(1, burst)
    }
}
