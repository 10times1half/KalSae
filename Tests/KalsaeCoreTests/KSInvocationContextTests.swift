import Foundation
import Testing

@testable import KalsaeCore

/// `KSInvocationContext.commandName` 이 `KSCommandRegistry.dispatch` 도중
/// 등록 이름으로 바인딩되고, 디스패치 외부에서는 `nil` 임을 검증한다.
@Suite("KSInvocationContext — commandName")
struct KSInvocationContextCommandNameTests {

    /// 핸들러 내부에서 자신의 등록 이름을 `KSInvocationContext.commandName`
    /// 으로 읽을 수 있어야 한다.
    @Test("commandName is bound to the dispatched name during the handler")
    func commandNameBoundDuringDispatch() async throws {
        let registry = KSCommandRegistry()
        // 핸들러는 TaskLocal 에서 읽은 이름을 그대로 응답 페이로드로 돌려준다.
        await registry.register("greet") { _ in
            let observed = KSInvocationContext.commandName ?? ""
            return .success(Data(observed.utf8))
        }

        let result = await registry.dispatch(name: "greet", args: Data())
        switch result {
        case .success(let data):
            #expect(String(data: data, encoding: .utf8) == "greet")
        case .failure(let error):
            Issue.record("dispatch failed: \(error)")
        }
    }

    /// `dispatch` 외부에서는 `commandName` 이 `nil` 이어야 한다.
    @Test("commandName is nil outside dispatch")
    func commandNameNilOutsideDispatch() {
        #expect(KSInvocationContext.commandName == nil)
    }
}
