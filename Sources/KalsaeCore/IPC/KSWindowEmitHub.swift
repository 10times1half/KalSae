/// 멀티 윈도우 emit 라우팅 허브.
///
/// 각 플랫폼 브리지는 초기화 시 이 허브에 자신을 등록하고 소멸 시
/// 등록을 해제한다. `KSApp.emit(event:payload:to:)`는 특정 창을 향해
/// 또는 열린 모든 창에 브로드캐스트하는 데 이 허브를 사용한다.
///
/// 모든 웹뷰/브리지 작업은 UI 스레드에서 이루어지므로 이 허브는
/// `@MainActor` 전용이다.
/// 창 레이블 → emit 클로저 매핑을 유지하는 공유 허브.
@MainActor
public final class KSWindowEmitHub: Sendable {
    /// 공유 싱글톤 인스턴스.
    public static let shared = KSWindowEmitHub()

    /// 창 레이블 → emit 싱크 클로저.
    public typealias EmitSink = @MainActor (String, any Encodable) throws(KSError) -> Void

    private var sinks: [String: EmitSink] = [:]

    private init() {}
    // Tests can create isolated instances via `@testable import KalsaeCore`.
    internal init(_testIsolated: Void = ()) {}

    /// 창 `label`에 대한 emit 싱크를 등록한다.
    public func register(label: String, sink: @escaping EmitSink) {
        sinks[label] = sink
    }

    /// 창 `label`에 대한 emit 싱크를 제거한다.
    public func unregister(label: String) {
        sinks.removeValue(forKey: label)
    }

    /// `event`를 방출한다.
    ///
    /// - `to label`이 `nil`이면 등록된 모든 창에 브로드캐스트한다.
    /// - 특정 레이블이 등록되어 있지 않으면 `noWindow` 에러를 던진다.
    public func emit(
        event: String,
        payload: any Encodable,
        to label: String?
    ) throws(KSError) {
        if let label {
            guard let sink = sinks[label] else {
                throw KSError(code: .invalidArgument, message: "No window registered for label '\(label)'")
            }
            try sink(event, payload)
        } else {
            for sink in sinks.values {
                try sink(event, payload)
            }
        }
    }
}
