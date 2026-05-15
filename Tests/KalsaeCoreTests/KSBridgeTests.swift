import Foundation
import Testing

@testable import KalsaeCore

/// `KSBridge` 프로토콜의 추상 계약 검증. 실제 플랫폼 브리지들은
/// `#if os(...)` 게이팅되어 있으므로 여기서는 프로토콜 표면이
/// 유지되는지 확인하는 모의 채택자를 통해 검증한다.
@Suite("KSBridge protocol")
@MainActor
struct KSBridgeTests {

    /// 모의 채택자. `KSBridge` 표면을 그대로 미러링하여 emit/onEvent
    /// 라운드트립을 시뮬레이션한다.
    final class MockBridge: KSBridge, @unchecked Sendable {
        let windowLabel: String
        var onEvent: (@MainActor (_ name: String, _ payload: Data?) -> Void)?
        var installed = false
        var emitted: [(String, Data)] = []

        init(windowLabel: String) {
            self.windowLabel = windowLabel
        }

        func install() throws(KSError) {
            installed = true
        }

        func emit(event name: String, payload: any Encodable) throws(KSError) {
            do {
                let data = try JSONEncoder().encode(KSEncodableBox(payload))
                emitted.append((name, data))
            } catch {
                throw KSError(code: .internal, message: "encode failed: \(error)")
            }
        }
    }

    private struct KSEncodableBox: Encodable {
        let value: any Encodable
        init(_ value: any Encodable) { self.value = value }
        func encode(to encoder: any Encoder) throws {
            try value.encode(to: encoder)
        }
    }

    @Test("프로토콜 표면: windowLabel / install / emit / onEvent 가 한 묶음으로 노출된다")
    func protocolSurfaceCompilesAndRoundTrips() throws {
        let bridge: any KSBridge = MockBridge(windowLabel: "main")

        #expect(bridge.windowLabel == "main")

        try bridge.install()

        struct Payload: Encodable { let v: Int }
        try bridge.emit(event: "greeting", payload: Payload(v: 42))

        guard let mock = bridge as? MockBridge else {
            Issue.record("downcast 실패")
            return
        }
        #expect(mock.installed == true)
        #expect(mock.emitted.count == 1)
        #expect(mock.emitted.first?.0 == "greeting")

        // JS->Swift 방향(onEvent) 시뮬레이션.
        var received: (String, Data?)?
        bridge.onEvent = { name, payload in
            received = (name, payload)
        }
        let payload = Data(#"{"hello":"world"}"#.utf8)
        bridge.onEvent?("js.event", payload)

        #expect(received?.0 == "js.event")
        #expect(received?.1 == payload)
    }
}
