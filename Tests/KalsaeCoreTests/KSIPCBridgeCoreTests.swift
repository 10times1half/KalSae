import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSIPCBridgeCore")
@MainActor
struct KSIPCBridgeCoreTests {

    /// Captures JSON frames posted to the JS side during a test.
    final class Recorder: @unchecked Sendable {
        var posts: [String] = []
    }

    /// Builds a bridge wired to a recorder and an inline hop (executes
    /// the response block on the same task that produced it). Tests run
    /// on `MainActor`, which is what platform hosts also assume.
    private func makeBridge(
        registry: KSCommandRegistry,
        recorder: Recorder
    ) -> KSIPCBridgeCore {
        KSIPCBridgeCore(
            registry: registry,
            logLabel: "test.ipc",
            post: { json throws(KSError) in
                recorder.posts.append(json)
            },
            hop: { block in
                // Inline-on-MainActor so the dispatch chain settles
                // before `wait()` returns control.
                Task { @MainActor in block() }
            })
    }

    @Test("encodeForJS inlines payload as raw JSON, not base64")
    func encodeInlinesPayload() throws {
        let payload = Data(#"{"a":1}"#.utf8)
        let msg = KSIPCMessage(
            kind: .response, id: "x",
            payload: payload, isError: false)
        let json = try KSIPCBridgeCore.encodeForJS(msg)
        #expect(json.contains(#""payload":{"a":1}"#))
        #expect(json.contains(#""kind":"response""#))
        #expect(json.contains(#""id":"x""#))
        #expect(json.contains(#""isError":false"#))
    }

    @Test("encodeForJS escapes control chars in id and name")
    func encodeEscapesStrings() throws {
        let msg = KSIPCMessage(kind: .event, name: "te\"st\nname")
        let json = try KSIPCBridgeCore.encodeForJS(msg)
        // JSON encoded should escape both quote and newline.
        #expect(json.contains(#"te\"st\nname"#))
    }

    @Test("invoke is dispatched and a response frame is posted")
    func invokeRoundTrip() async throws {
        let registry = KSCommandRegistry()
        await registry.register("echo") { args in .success(args) }
        let recorder = Recorder()
        let bridge = makeBridge(registry: registry, recorder: recorder)

        bridge.handleInbound(
            #"{"kind":"invoke","id":"7","name":"echo","payload":{"x":42}}"#)

        // Allow the detached dispatch + hop to settle.
        try await waitUntil { recorder.posts.count >= 1 }
        #expect(recorder.posts.count == 1)
        let frame = recorder.posts[0]
        #expect(frame.contains(#""kind":"response""#))
        #expect(frame.contains(#""id":"7""#))
        #expect(frame.contains(#""isError":false"#))
        // The echo handler returns the raw arg payload re-encoded.
        #expect(frame.contains(#""x":42"#))
    }

    @Test("Unknown commands produce an error response, not a crash")
    func invokeUnknownCommandReturnsError() async throws {
        let registry = KSCommandRegistry()
        let recorder = Recorder()
        let bridge = makeBridge(registry: registry, recorder: recorder)

        bridge.handleInbound(
            #"{"kind":"invoke","id":"9","name":"missing"}"#)

        try await waitUntil { recorder.posts.count >= 1 }
        let frame = recorder.posts[0]
        #expect(frame.contains(#""isError":true"#))
        #expect(frame.contains("commandNotFound"))
    }

    @Test("Malformed inbound is dropped silently, no posts")
    func malformedDropped() async throws {
        let registry = KSCommandRegistry()
        let recorder = Recorder()
        let bridge = makeBridge(registry: registry, recorder: recorder)
        bridge.handleInbound("not json")
        bridge.handleInbound(#"{"kind":"unknown"}"#)
        // Give the executor a tick.
        try await Task.sleep(for: .milliseconds(10))
        #expect(recorder.posts.isEmpty)
    }

    @Test("event dispatches to onEvent without posting a response")
    func eventForwarded() async throws {
        let registry = KSCommandRegistry()
        let recorder = Recorder()
        let bridge = makeBridge(registry: registry, recorder: recorder)
        var received: (String, Data?)?
        bridge.onEvent = { name, payload in received = (name, payload) }
        bridge.handleInbound(
            #"{"kind":"event","name":"hello","payload":[1,2]}"#)
        try await Task.sleep(for: .milliseconds(10))
        #expect(received?.0 == "hello")
        #expect(recorder.posts.isEmpty)
    }

    @Test("emit serializes payloads inline and posts an event frame")
    func emitInlinesPayload() throws {
        let registry = KSCommandRegistry()
        let recorder = Recorder()
        let bridge = makeBridge(registry: registry, recorder: recorder)

        struct P: Encodable { let v: Int }
        try bridge.emit(event: "ping", payload: P(v: 3))
        #expect(recorder.posts.count == 1)
        let frame = recorder.posts[0]
        #expect(frame.contains(#""kind":"event""#))
        #expect(frame.contains(#""name":"ping""#))
        #expect(frame.contains(#""payload":{"v":3}"#))
    }

    // MARK: - Security: payload size guard

    @Test("Oversized inbound frame is dropped without posting a response")
    func oversizedFrameDropped() async throws {
        let registry = KSCommandRegistry()
        let recorder = Recorder()
        let bridge = makeBridge(registry: registry, recorder: recorder)

        // Build a frame that exceeds maxFrameBytes (16 MB).
        let bigValue = String(repeating: "a", count: KSIPCBridgeCore.maxFrameBytes + 1)
        let frame = #"{"kind":"invoke","id":"1","name":"echo","payload":""# + bigValue + #"""}"#
        bridge.handleInbound(frame)

        try await Task.sleep(for: .milliseconds(20))
        #expect(recorder.posts.isEmpty, "Oversized frame must be silently dropped")
    }

    // MARK: - Security: XSS-safe escaping

    @Test("encodeForJS escapes </script> in name field")
    func encodeEscapesScriptTag() throws {
        let msg = KSIPCMessage(kind: .event, name: "</script><script>alert(1)//")
        let json = try KSIPCBridgeCore.encodeForJS(msg)
        #expect(!json.contains("</script>"), "Raw </script> must not appear in encoded frame")
        #expect(json.contains("<\\/script>"), "Forward-slash must be escaped as \\/")
    }

    @Test("encodeForJS escapes U+2028 and U+2029 in payload")
    func encodeEscapesLineTerminators() throws {
        // Build a payload that contains U+2028 (LINE SEPARATOR) inside a JSON string.
        let dangerousString = "line\u{2028}sep\u{2029}end"
        let payloadData = (try? JSONEncoder().encode(dangerousString)) ?? Data()
        let msg = KSIPCMessage(kind: .event, name: "test", payload: payloadData)
        let json = try KSIPCBridgeCore.encodeForJS(msg)
        #expect(!json.contains("\u{2028}"), "U+2028 must be escaped")
        #expect(!json.contains("\u{2029}"), "U+2029 must be escaped")
        #expect(json.contains("\\u2028"))
        #expect(json.contains("\\u2029"))
    }

    // MARK: - helpers

    /// Polls `predicate` up to ~1s with 5ms ticks. Used because the
    /// bridge's dispatch goes through `Task.detached` + a hop, which
    /// means the response post is not synchronous with `handleInbound`.
    private func waitUntil(
        timeoutMs: Int = 1000,
        _ predicate: @MainActor () -> Bool
    ) async throws {
        var elapsed = 0
        while !predicate() && elapsed < timeoutMs {
            try await Task.sleep(for: .milliseconds(5))
            elapsed += 5
        }
        #expect(predicate(), "wait predicate timed out after \(timeoutMs)ms")
    }
}
