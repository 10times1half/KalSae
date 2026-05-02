import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSWindowEmitHub")
@MainActor
struct KSWindowEmitHubTests {

    // ──────────────────────────────────────────────────────────────
    // Helpers
    // ──────────────────────────────────────────────────────────────

    final class ReceivedEvent: @unchecked Sendable {
        var events: [(event: String, window: String)] = []
    }

    private func makeSink(
        label: String,
        recorder: ReceivedEvent
    ) -> KSWindowEmitHub.EmitSink {
        { event, _ throws(KSError) in
            recorder.events.append((event: event, window: label))
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Registration + emit routing
    // ──────────────────────────────────────────────────────────────

    @Test("emit to specific window delivers to that window only")
    func emitToWindowDelivers() throws {
        let hub = KSWindowEmitHub(_testIsolated: ())
        let rec = ReceivedEvent()

        hub.register(label: "win-a", sink: makeSink(label: "win-a", recorder: rec))
        hub.register(label: "win-b", sink: makeSink(label: "win-b", recorder: rec))

        try hub.emit(event: "ping", payload: "hello", to: "win-a")

        #expect(rec.events.count == 1)
        #expect(rec.events[0].window == "win-a")
        #expect(rec.events[0].event == "ping")
    }

    @Test("emit to nil broadcasts to all registered windows")
    func emitBroadcast() throws {
        let hub = KSWindowEmitHub(_testIsolated: ())
        let rec = ReceivedEvent()

        hub.register(label: "win-a", sink: makeSink(label: "win-a", recorder: rec))
        hub.register(label: "win-b", sink: makeSink(label: "win-b", recorder: rec))

        try hub.emit(event: "update", payload: 42, to: String?.none)

        #expect(rec.events.count == 2)
        let labels = Set(rec.events.map(\.window))
        #expect(labels == ["win-a", "win-b"])
    }

    @Test("emit to unknown label throws noWindow error")
    func emitUnknownLabel() {
        let hub = KSWindowEmitHub(_testIsolated: ())

        #expect(throws: KSError.self) {
            try hub.emit(event: "test", payload: "x", to: "missing")
        }
    }

    @Test("unregister removes window from routing")
    func unregisterRemoves() throws {
        let hub = KSWindowEmitHub(_testIsolated: ())
        let rec = ReceivedEvent()

        hub.register(label: "win-a", sink: makeSink(label: "win-a", recorder: rec))
        hub.register(label: "win-b", sink: makeSink(label: "win-b", recorder: rec))
        hub.unregister(label: "win-a")

        try hub.emit(event: "ping", payload: "x", to: String?.none)

        #expect(rec.events.count == 1)
        #expect(rec.events[0].window == "win-b")
    }

    @Test("re-register replaces the sink")
    func reRegisterReplacesSink() throws {
        let hub = KSWindowEmitHub(_testIsolated: ())
        let recOld = ReceivedEvent()
        let recNew = ReceivedEvent()

        hub.register(label: "win-a", sink: makeSink(label: "win-a", recorder: recOld))
        hub.register(label: "win-a", sink: makeSink(label: "win-a", recorder: recNew))

        try hub.emit(event: "ping", payload: "x", to: "win-a")

        #expect(recOld.events.isEmpty)
        #expect(recNew.events.count == 1)
    }
}

// ──────────────────────────────────────────────────────────────────────
// KSInvocationContext
// ──────────────────────────────────────────────────────────────────────

@Suite("KSInvocationContext")
struct KSInvocationContextTests {

    @Test("windowLabel defaults to nil")
    func defaultsToNil() {
        #expect(KSInvocationContext.windowLabel == nil)
    }

    @Test("withValue propagates label to inner scope")
    func propagatesLabel() async {
        let label = await KSInvocationContext.$windowLabel.withValue("main") {
            KSInvocationContext.windowLabel
        }
        #expect(label == "main")
    }

    @Test("label is nil outside withValue scope")
    func nilOutsideScope() async {
        await KSInvocationContext.$windowLabel.withValue("scoped") {
            _ = KSInvocationContext.windowLabel
        }
        #expect(KSInvocationContext.windowLabel == nil)
    }

    @Test("windowLabel propagates through detached Task")
    func propagatesThroughDetachedTask() async {
        let captured = await KSInvocationContext.$windowLabel.withValue("settings") {
            await Task.detached {
                KSInvocationContext.windowLabel
            }.value
        }
        // TaskLocal values do NOT propagate to Task.detached by design;
        // KSIPCBridgeCore captures the value before the Task and passes it
        // via withValue inside the detached task body.
        // Verify isolation: detached task sees nil without explicit injection.
        #expect(captured == nil)
    }

    @Test("withValue inside detached task sets label correctly")
    func withValueInDetachedTask() async {
        let captured = await Task.detached {
            await KSInvocationContext.$windowLabel.withValue("injected") {
                KSInvocationContext.windowLabel
            }
        }.value
        #expect(captured == "injected")
    }
}

// ──────────────────────────────────────────────────────────────────────
// KSIPCBridgeCore windowLabel injection
// ──────────────────────────────────────────────────────────────────────

private final class Box<T: Sendable>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

@Suite("KSIPCBridgeCore ✦ invocation context")
@MainActor
struct KSIPCBridgeCoreInvocationContextTests {

    private func wait(seconds: Double = 0.5) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @Test("windowLabel is set during command dispatch")
    func windowLabelDuringDispatch() async throws {
        let registry = KSCommandRegistry()
        let captured = Box<String?>("not-set")

        await registry.register("getLabel") { args in
            captured.value = KSInvocationContext.windowLabel
            return .success(args)
        }

        let bridge = KSIPCBridgeCore(
            registry: registry,
            windowLabel: "settings",
            logLabel: "test.invocation",
            post: { _ throws(KSError) in },
            hop: { block in Task { @MainActor in block() } })

        let frame = #"{"kind":"invoke","id":"1","name":"getLabel","payload":"\"x\""}"#
        bridge.handleInbound(frame)

        await wait()

        #expect(captured.value == "settings")
    }

    @Test("windowLabel is nil when not set on bridge")
    func windowLabelNilWhenNotSet() async throws {
        let registry = KSCommandRegistry()
        let captured = Box<String?>("not-set")

        await registry.register("getLabel") { args in
            captured.value = KSInvocationContext.windowLabel
            return .success(args)
        }

        let bridge = KSIPCBridgeCore(
            registry: registry,
            logLabel: "test.invocation.nil",
            post: { _ throws(KSError) in },
            hop: { block in Task { @MainActor in block() } })

        let frame = #"{"kind":"invoke","id":"1","name":"getLabel","payload":"\"x\""}"#
        bridge.handleInbound(frame)

        await wait()

        #expect(captured.value == nil)
    }
}
