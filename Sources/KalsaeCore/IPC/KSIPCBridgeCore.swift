public import Foundation
internal import Logging

// MARK: - Wire types (shared across platforms)

/// Wire-level inbound IPC payload from JS. Mirrors `KSRuntimeJS.source`'s
/// `__KS_.invoke` / `emit` envelope.
///
/// `payload` is preserved as raw JSON bytes so registered command
/// handlers can decode it themselves.
///
/// Internal to KalsaeCore — the bridge owns the wire shape; consumers
/// see only `KSIPCMessage` and the `KSCommandRegistry` API.
internal struct KSIPCWireInbound: Decodable, Sendable {
    enum Kind: String, Decodable, Sendable { case invoke, event }
    let kind: Kind
    let id: String?
    let name: String?
    let payload: Data?

    private enum CodingKeys: String, CodingKey {
        case kind, id, name, payload
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try c.decode(Kind.self, forKey: .kind)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        if c.contains(.payload) {
            let value = try c.decode(KSAnyJSON.self, forKey: .payload)
            self.payload = try JSONEncoder().encode(value)
        } else {
            self.payload = nil
        }
    }
}

/// Minimal "any JSON" type used to round-trip arbitrary payloads
/// without losing structure. Internal — used only by
/// `KSIPCWireInbound` to preserve the inbound `payload` field.
internal enum KSAnyJSON: Codable, Sendable {
    case null
    case bool(Bool)
    case double(Double)
    case string(String)
    case array([KSAnyJSON])
    case object([String: KSAnyJSON])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([KSAnyJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: KSAnyJSON].self) {
            self = .object(o); return
        }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unknown JSON value")
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Bridge core

/// Platform-agnostic IPC bridge: decodes inbound frames, dispatches
/// `invoke` to a `KSCommandRegistry`, encodes responses, and emits
/// outbound `event` frames.
///
/// Each platform supplies two closures:
/// - `post`: how to send a JSON string to the JS side (UI-thread only).
/// - `hop`:  how to schedule a `@MainActor` closure on the UI thread
///   from any thread. On macOS this can be a plain `Task { @MainActor }`
///   because AppKit's run-loop pumps the `MainActor` executor; on
///   Windows it must wrap `PostMessageW(WM_KS_JOB)`; on Linux it must
///   wrap `g_idle_add`.
@MainActor
public final class KSIPCBridgeCore {
    public typealias PostJSON = @MainActor (String) throws(KSError) -> Void
    public typealias MainHop = @Sendable (@escaping @MainActor () -> Void) -> Void

    private let registry: KSCommandRegistry
    private let post: PostJSON
    private let hop: MainHop
    private let log: Logger

    /// Sink for `emit` messages from JS.
    public var onEvent: (@MainActor (String, Data?) -> Void)?

    public init(
        registry: KSCommandRegistry,
        logLabel: String,
        post: @escaping PostJSON,
        hop: @escaping MainHop
    ) {
        self.registry = registry
        self.log = Logger(label: logLabel)
        self.post = post
        self.hop = hop
    }

    /// Decodes one inbound frame and dispatches it. Called from the UI
    /// thread by the platform host's message handler.
    public func handleInbound(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            log.warning("Non-UTF8 inbound IPC frame (dropped)")
            return
        }
        let msg: KSIPCWireInbound
        do {
            msg = try JSONDecoder().decode(KSIPCWireInbound.self, from: data)
        } catch {
            log.warning("Malformed inbound IPC frame: \(error)")
            return
        }
        switch msg.kind {
        case .invoke:
            guard let id = msg.id, let name = msg.name else {
                log.warning("invoke without id/name")
                return
            }
            let args = msg.payload ?? Data("null".utf8)
            let registry = self.registry
            let hop = self.hop
            // 디스패치는 `Task.detached`로 백그라운드에서 수행한 뒤 hop을
            // 통해 UI 스레드로 복귀해 응답을 송신한다. Mac은 AppKit
            // 런루프가 MainActor 실행기를 펌프하므로 hop이 단순 `Task {`
            // 로 구현되어도 동작하고, Linux/Windows는 g_idle_add /
            // PostMessageW로 명시적으로 복귀해야 한다.
            Task.detached { [weak self] in
                let result = await registry.dispatch(name: name, args: args)
                hop {
                    self?.sendResponse(id: id, result: result)
                }
            }
        case .event:
            guard let name = msg.name else { return }
            onEvent?(name, msg.payload)
        }
    }

    private func sendResponse(id: String, result: Result<Data, KSError>) {
        let message: KSIPCMessage
        switch result {
        case .success(let data):
            message = KSIPCMessage(kind: .response, id: id, payload: data,
                                   isError: false)
        case .failure(let err):
            let encoded = (try? JSONEncoder().encode(err)) ?? Data("{}".utf8)
            message = KSIPCMessage(kind: .response, id: id, payload: encoded,
                                   isError: true)
        }
        do {
            let json = try Self.encodeForJS(message)
            try post(json)
        } catch {
            log.error("Failed to post response: \(error)")
        }
    }

    /// Emits a fire-and-forget event to JS (`window.__KS_.listen(name, cb)`).
    public func emit(event name: String,
                     payload: any Encodable) throws(KSError) {
        let payloadData: Data
        do {
            payloadData = try JSONEncoder().encode(KSAnyEncodable(payload))
        } catch {
            throw KSError(code: .commandEncodeFailed,
                          message: "emit(\(name)): \(error)")
        }
        let msg = KSIPCMessage(kind: .event, name: name, payload: payloadData)
        let json: String
        do {
            json = try Self.encodeForJS(msg)
        } catch {
            throw KSError(code: .commandEncodeFailed,
                          message: "emit(\(name)) encode: \(error)")
        }
        try post(json)
    }

    // MARK: - JSON assembly

    /// Re-encodes a `KSIPCMessage` so that `payload` is an inline JSON
    /// value rather than a base64-encoded `Data` blob. Internal — only
    /// the bridge itself calls this when posting frames to JS.
    internal static func encodeForJS(_ msg: KSIPCMessage) throws -> String {
        var parts: [String] = []
        parts.append("\"kind\":\"\(msg.kind.rawValue)\"")
        if let id = msg.id { parts.append("\"id\":\(jsonString(id))") }
        if let name = msg.name { parts.append("\"name\":\(jsonString(name))") }
        if let payload = msg.payload,
           let s = String(data: payload, encoding: .utf8) {
            parts.append("\"payload\":\(s)")
        } else {
            parts.append("\"payload\":null")
        }
        if let e = msg.isError { parts.append("\"isError\":\(e)") }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private static func jsonString(_ s: String) -> String {
        let data = (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }
}

/// Type-erased encodable wrapper used by `emit`. Internal — apps pass
/// `any Encodable` directly to `emit(_:payload:)`.
internal struct KSAnyEncodable: Encodable {
    let base: any Encodable
    init(_ base: any Encodable) { self.base = base }
    func encode(to encoder: any Encoder) throws {
        try base.encode(to: encoder)
    }
}
