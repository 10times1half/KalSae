#if os(Windows)
    import Testing
    import Foundation
    import WinSDK
    import CKalsaeWV2

    /// Bug 3 회귀 — `KSWV2_RegisterDropTarget` / `KSWV2_RevokeDropTarget` 의
    /// 대칭성 단언.
    ///
    /// 원래 버그: 부모 HWND 에 register 했을 때 WebView2 가 만든 자식 HWND
    /// 까지 등록되지만, revoke 는 부모만 풀어 자식 등록이 누수되며
    /// `g_dropTargets` 가 영구히 커졌다 (드롭 시 X 커서 유지).
    ///
    /// 본 테스트는 부모 + 명시적 자식 STATIC HWND 들을 생성해
    /// register → 카운트 증가, revoke → 카운트 0 임을 단언한다.
    @Suite(
        "CKalsaeWV2 — Drop target registration symmetry",
        .serialized)
    struct KSWebView2DropRegistrationTests {

        /// 더미 콜백 — 실제 드롭 이벤트는 발생하지 않으므로 사용되지 않는다.
        private static let dummyCB: KSWV2DropCB = { _, _, _, _, _, _ in 0 }

        /// 부모 HWND + 2 자식 HWND 에 등록 → 카운트 ≥ 3,
        /// 부모에 대해 revoke → 카운트 == 0.
        ///
        /// `RegisterDragDrop` 은 호출 스레드가 **STA 로 OleInitialize** 되어야
        /// 한다. 같은 프로세스의 다른 테스트(WebView2 통합 등)가 메인 스레드를
        /// MTA 로 초기화해 둔 경우 `OleInitializeOnce()` 는 `RPC_E_CHANGED_MODE`
        /// 를 돌려준다. 그래서 본 테스트는 전용 신규 스레드에서 실행한다.
        @Test("register parent + 2 children, revoke parent → count 0")
        func registerAndRevokeSymmetry() throws {
            final class Box: @unchecked Sendable {
                var ok: Bool = false
                var detail: String = ""
            }
            let box = Box()
            let done = DispatchSemaphore(value: 0)

            Thread.detachNewThread {
                defer { done.signal() }

                let baseline = KSWV2_DebugGetRegisteredCount()
                let oleHR = KSWV2_OleInitializeOnce()
                guard oleHR == 0 else {
                    box.detail = "OleInitializeOnce failed hr=\(String(oleHR, radix: 16))"
                    return
                }

                let parent = "STATIC".withCString(encodedAs: UTF16.self) { cls in
                    CreateWindowExW(
                        0, cls, nil, DWORD(WS_POPUP),
                        -10_000, -10_000, 10, 10,
                        nil, nil, GetModuleHandleW(nil), nil)
                }
                guard let parent else {
                    box.detail = "CreateWindowExW(parent) failed"
                    return
                }
                defer { _ = DestroyWindow(parent) }

                let child1 = "STATIC".withCString(encodedAs: UTF16.self) { cls in
                    CreateWindowExW(
                        0, cls, nil, DWORD(WS_CHILD),
                        0, 0, 5, 5,
                        parent, nil, GetModuleHandleW(nil), nil)
                }
                guard let child1 else {
                    box.detail = "CreateWindowExW(child1) failed"
                    return
                }
                defer { _ = DestroyWindow(child1) }

                let child2 = "STATIC".withCString(encodedAs: UTF16.self) { cls in
                    CreateWindowExW(
                        0, cls, nil, DWORD(WS_CHILD),
                        0, 0, 5, 5,
                        parent, nil, GetModuleHandleW(nil), nil)
                }
                guard let child2 else {
                    box.detail = "CreateWindowExW(child2) failed"
                    return
                }
                defer { _ = DestroyWindow(child2) }

                let rc = KSWV2_RegisterDropTarget(
                    UnsafeMutableRawPointer(parent), nil, Self.dummyCB)
                guard rc == 0 else {
                    box.detail = "RegisterDropTarget rc=\(String(rc, radix: 16))"
                    return
                }

                let afterRegister = KSWV2_DebugGetRegisteredCount()
                guard afterRegister >= baseline + 3 else {
                    box.detail =
                        "afterRegister=\(afterRegister) baseline=\(baseline)"
                    return
                }

                KSWV2_RevokeDropTarget(UnsafeMutableRawPointer(parent))
                let afterRevoke = KSWV2_DebugGetRegisteredCount()
                guard afterRevoke == baseline else {
                    box.detail =
                        "leftover=\(afterRevoke - baseline) after revoke"
                    return
                }

                box.ok = true
            }
            done.wait()

            #expect(box.ok, "drop registration symmetry: \(box.detail)")
        }
    }
#endif
