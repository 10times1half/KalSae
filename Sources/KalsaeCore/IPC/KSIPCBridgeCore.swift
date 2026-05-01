public import Foundation
internal import Logging

// MARK: - 와이어 타입 (플랫폼 간 공유)

/// JS로부터의 와이어 수준 인바운드 IPC 페이로드. `KSRuntimeJS.source`의
/// `__KS_.invoke` / `emit` 봉투를 미러링한다.
///
/// `payload`는 원시 JSON 바이트로 보존되어 등록된 명령 핸들러가
/// 직접 디코딩할 수 있다.
///
/// KalsaeCore 내부 — 브리지가 와이어 형상을 소유하며; 소비자는
/// `KSIPCMessage`와 `KSCommandRegistry` API만 본다.
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

/// 구조를 잃지 않고 임의의 페이로드를 왕복하는 데 사용되는
/// 최소 "any JSON" 타입. 내부 — 인바운드 `payload` 필드를 보존하기 위해
/// `KSIPCWireInbound`에서만 사용된다.
internal enum KSAnyJSON: Codable, Sendable {
    case null
    case bool(Bool)
    case double(Double)
    case string(String)
    case array([KSAnyJSON])
    case object([String: KSAnyJSON])

    init(from decoder: any Decoder) throws {
        // Codable 프로토콜 — untyped throws (변경 불가)
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
        // Codable 프로토콜 — untyped throws (변경 불가)
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

// MARK: - 브리지 코어

/// 플랫폼 독립적 IPC 브리지: 인바운드 프레임을 디코딩하고,
/// `invoke`를 `KSCommandRegistry`로 디스패치하며, 응답을 인코딩하고,
/// 아웃바운드 `event` 프레임을 방출한다.
///
/// 각 플랫폼은 두 개의 클로저를 제공한다:
/// - `post`: JS 측에 JSON 문자열을 보내는 방법 (UI 스레드 전용).
/// - `hop`:  임의 스레드에서 UI 스레드의 `@MainActor` 클로저를
///   스케줄링하는 방법. macOS에서는 AppKit의 런루프가 `MainActor`
///   실행기를 펌프하므로 단순 `Task { @MainActor }`로 가능하지만,
///   Windows에서는 `PostMessageW(WM_KS_JOB)`로, Linux에서는
///   `g_idle_add`로 감싸야 한다.
@MainActor
public final class KSIPCBridgeCore {
    public typealias PostJSON = @MainActor (String) throws(KSError) -> Void
    public typealias MainHop = @Sendable (@escaping @MainActor () -> Void) -> Void

    /// 최대 인바운드 프레임 크기(바이트). 이보다 큰 프레임은 악의적인
    /// 웹 콘텐츠로 인한 OOM/CPU DoS를 방지하기 위해 조용히 폐기된다.
    public static let maxFrameBytes: Int = 16 * 1024 * 1024  // 16 MB

    private let registry: KSCommandRegistry
    private let post: PostJSON
    private let hop: MainHop
    private let log: Logger

    /// JS로부터의 `emit` 메시지 싱크.
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

    /// 인바운드 프레임 하나를 디코딩하고 디스패치한다. 플랫폼 호스트의
    /// 메시지 핸들러에 의해 UI 스레드에서 호출된다.
    public func handleInbound(_ text: String) {
        let byteCount = text.utf8.count
        guard byteCount <= Self.maxFrameBytes else {
            log.warning("Inbound IPC frame exceeds size limit (\(byteCount) bytes); dropped")
            return
        }
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

    /// JS에 발사 후 망각 이벤트를 방출한다 (`window.__KS_.listen(name, cb)`).
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

    // MARK: - JSON 조립

    /// `KSIPCMessage`를 재인코딩하여 `payload`가 base64 인코딩된
    /// `Data` 블롭이 아닌 인라인 JSON 값이 되도록 한다. 내부 —
    /// 프레임을 JS에 게시할 때 브리지 자체만 호출한다.
    internal static func encodeForJS(_ msg: KSIPCMessage) throws -> String {
        // Codable 프로토콜 예외 — untyped throws (JSONEncoder 콜백)
        var parts: [String] = []
        parts.append("\"kind\":\"\(msg.kind.rawValue)\"")
        if let id = msg.id { parts.append("\"id\":\(jsonString(id))") }
        if let name = msg.name { parts.append("\"name\":\(jsonString(name))") }
        if let payload = msg.payload,
           let s = String(data: payload, encoding: .utf8) {
            parts.append("\"payload\":\(escapeJSONText(s))")
        } else {
            parts.append("\"payload\":null")
        }
        if let e = msg.isError { parts.append("\"isError\":\(e)") }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private static func jsonString(_ s: String) -> String {
        let data = (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8)
        var out = String(data: data, encoding: .utf8) ?? "\"\""
        // XSS 안전: </script> 주입 및 JS 줄 트리미얠터 문제 방지.
        out = out.replacingOccurrences(of: "</", with: "<\\/")
        out = out.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        out = out.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return out
    }

    /// 이미 형성된 JSON 텍스트 조각에 XSS 안전 이스케이프를 적용한다.
    /// `<\/`는 유효한 JSON(슬래시는 이스케이프 가능)이므로 안전하다.
    private static func escapeJSONText(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(of: "</", with: "<\\/")
        out = out.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        out = out.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return out
    }
}

/// `emit`에서 사용되는 타입 지워진 인코더블 래퍼. 내부 — 앱은
/// `any Encodable`을 `emit(_:payload:)`에 직접 전달한다.
internal struct KSAnyEncodable: Encodable {
    let base: any Encodable
    init(_ base: any Encodable) { self.base = base }
    func encode(to encoder: any Encoder) throws {
        // Codable 프로토콜 — untyped throws (변경 불가)
        try base.encode(to: encoder)
    }
}
