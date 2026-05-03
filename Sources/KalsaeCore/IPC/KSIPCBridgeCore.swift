public import Foundation
/// JS로부터의 와이어 수준 인바운드 IPC 페이로드. `KSRuntimeJS.source`의
/// `__KS_.invoke` / `emit` 봉투를 미러링한다.
///
/// `payload`는 원시 JSON 바이트로 보존되어 등록된 명령 핸들러가
/// 직접 디코딩할 수 있다.
///
/// KalsaeCore 내부 — 브리지가 와이어 형상을 소유하며; 소비자는
/// `KSIPCMessage`와 `KSCommandRegistry` API만 본다.
internal import Logging

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

/// `emit`에서 사용되는 타입 지워진 인코더블 래퍼. 내부 — 앱은
/// `any Encodable`을 `emit(_:payload:)`에 직접 전달한다.
@MainActor
public final class KSIPCBridgeCore {
    public typealias PostJSON = @MainActor (String) throws(KSError) -> Void
    public typealias MainHop = @Sendable (@escaping @MainActor () -> Void) -> Void

    /// 최대 인바운드 프레임 크기(바이트). 이보다 큰 프레임은 악의적인
    /// 웹 콘텐츠로 인한 OOM/CPU DoS를 방지하기 위해 조용히 폐기된다.
    public static let maxFrameBytes: Int = 16 * 1024 * 1024  // 16 MB

    /// 매 호출마다 JSONEncoder 인스턴스를 새로 만드는 비용을 절감하는 공유 인스턴스.
    /// 모든 사용처가 @MainActor로 격리되어 있어 단일 스레드에서만 접근된다.
    private static let _sharedEncoder = JSONEncoder()

    private let registry: KSCommandRegistry
    private let post: PostJSON
    private let hop: MainHop
    private let log: Logger
    private let windowLabel: String?

    /// JS로부터의 `emit` 메시지 싱크.
    public var onEvent: (@MainActor (String, Data?) -> Void)?

    public init(
        registry: KSCommandRegistry,
        windowLabel: String? = nil,
        logLabel: String,
        post: @escaping PostJSON,
        hop: @escaping MainHop
    ) {
        self.registry = registry
        self.windowLabel = windowLabel
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
        // JSONSerialization으로 직접 파싱 — KSAnyJSON 트리 생성 + 재인코딩(2단계) 없이
        // 페이로드 원본 바이트를 보존한다. JSONDecoder+KSAnyJSON+JSONEncoder 대비
        // 중간 할당과 enum 트리 구성 비용을 제거한다.
        let top: [String: Any]
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log.warning("Inbound IPC frame is not a JSON object (dropped)")
                return
            }
            top = obj
        } catch {
            log.warning("Malformed inbound IPC frame: \(error)")
            return
        }
        guard let kindStr = top["kind"] as? String else {
            log.warning("Inbound IPC frame missing 'kind' (dropped)")
            return
        }
        switch kindStr {
        case "invoke":
            guard let id = top["id"] as? String, let name = top["name"] as? String else {
                log.warning("invoke without id/name")
                return
            }
            // 페이로드를 1회 직렬화 — KSAnyJSON decode→encode 2단계 대신 JSONSerialization 1단계.
            let args = Self.rawJSONBytes(top["payload"])
            let registry = self.registry
            let hop = self.hop
            let wl = self.windowLabel
            // 디스패치는 `Task.detached`로 백그라운드에서 수행한 뒤 hop을
            // 통해 UI 스레드로 복귀해 응답을 송신한다.
            // KSInvocationContext.windowLabel을 TaskLocal로 주입해
            // 명령 핸들러가 어느 창에서 호출됐는지 확인할 수 있도록 한다.
            Task.detached { [weak self] in
                let result = await KSInvocationContext.$windowLabel.withValue(wl) {
                    await registry.dispatch(name: name, args: args)
                }
                hop {
                    self?.sendResponse(id: id, result: result)
                }
            }
        case "event":
            guard let name = top["name"] as? String else { return }
            // payload 키 부재 → nil, null → Data("null"), 그 외 → 직렬화 bytes.
            let pd: Data?
            switch top["payload"] {
            case .none: pd = nil
            case .some(let v) where v is NSNull: pd = Data("null".utf8)
            case .some(let v): pd = Self.rawJSONBytes(v)
            }
            onEvent?(name, pd)
        default:
            log.warning("Unknown IPC kind '\(kindStr)' (dropped)")
        }
    }

    /// `Foundation.Any?` 값을 JSON `Data`로 변환한다.
    /// nil / NSNull → `"null"` bytes. 딕셔너리·배열은 직렬화, 스칼라는
    /// 1-원소 배열 `[v]`로 감싸 직렬화 후 앞뒤 `[` `]`를 제거한다
    /// (JSONSerialization이 스칼라 루트를 직렬화할 수 없기 때문).
    private static func rawJSONBytes(_ value: Any?) -> Data {
        guard let value, !(value is NSNull) else { return Data("null".utf8) }
        if JSONSerialization.isValidJSONObject(value) {
            return (try? JSONSerialization.data(withJSONObject: value)) ?? Data("null".utf8)
        }
        // 스칼라(숫자·문자열·불리언): 1-원소 배열로 감싸 직렬화 후 [ ] 제거.
        guard let wrapped = try? JSONSerialization.data(withJSONObject: [value]),
            wrapped.count >= 2
        else { return Data("null".utf8) }
        return Data(wrapped[1..<wrapped.count - 1])
    }

    private func sendResponse(id: String, result: Result<Data, KSError>) {
        let message: KSIPCMessage
        switch result {
        case .success(let data):
            message = KSIPCMessage(
                kind: .response, id: id, payload: data,
                isError: false)
        case .failure(let err):
            let encoded = (try? Self._sharedEncoder.encode(err)) ?? Data("{}".utf8)
            message = KSIPCMessage(
                kind: .response, id: id, payload: encoded,
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
    public func emit(
        event name: String,
        payload: any Encodable
    ) throws(KSError) {
        let payloadData: Data
        do {
            payloadData = try Self._sharedEncoder.encode(KSAnyEncodable(payload))
        } catch {
            throw KSError(
                code: .commandEncodeFailed,
                message: "emit(\(name)): \(error)")
        }
        let msg = KSIPCMessage(kind: .event, name: name, payload: payloadData)
        let json: String
        do {
            json = try Self.encodeForJS(msg)
        } catch {
            throw KSError(
                code: .commandEncodeFailed,
                message: "emit(\(name)) encode: \(error)")
        }
        try post(json)
    }

    // MARK: - JSON 조립

    /// `KSIPCMessage`를 재인코딩하여 `payload`가 base64 인코딩된
    /// `Data` 블롭이 아닌 인라인 JSON 값이 되도록 한다. 내부 —
    /// 프레임을 JS에 게시할 때 브리지 자체만 호출한다.
    ///
    /// 중간 배열/문자열 할당 없이 단일 `String` 조립,
    /// 모든 escape를 단일 유니코드 스칼라 스캔으로 처리한다.
    internal static func encodeForJS(_ msg: KSIPCMessage) throws -> String {
        var out = String()
        out.reserveCapacity(128)
        out.append("{\"kind\":\"")
        out.append(msg.kind.rawValue)  // enum rawValue는 ASCII 안전 토큰
        out.append("\"")
        if let id = msg.id {
            out.append(",\"id\":")
            appendJSEscaped(into: &out, id)
        }
        if let name = msg.name {
            out.append(",\"name\":")
            appendJSEscaped(into: &out, name)
        }
        if let payload = msg.payload, let s = String(data: payload, encoding: .utf8) {
            out.append(",\"payload\":")
            appendJSEscapedRaw(into: &out, s)
        } else {
            out.append(",\"payload\":null")
        }
        if let e = msg.isError {
            out.append(",\"isError\":")
            out.append(e ? "true" : "false")
        }
        out.append("}")
        return out
    }

    /// JSON 문자열 값을 `"` 로 감싸 JS 삽입 안전 형태로 `out`에 단일 패스 이스케이핑한다.
    /// JSON 표준 이스케이프(`\"`, `\\`, `\n` 등)와 XSS 안전 이스케이프
    /// (`<\/`, `\u2028`, `\u2029`)를 하나의 유니코드 스칼라 스캔으로 처리한다.
    private static func appendJSEscaped(into out: inout String, _ s: String) {
        out.append("\"")
        for u in s.unicodeScalars {
            switch u.value {
            case 0x22: out.append("\\\"")
            case 0x5C: out.append("\\\\")
            case 0x08: out.append("\\b")
            case 0x09: out.append("\\t")
            case 0x0A: out.append("\\n")
            case 0x0C: out.append("\\f")
            case 0x0D: out.append("\\r")
            case 0x00...0x1F:
                out.append("\\u00")
                let h = String(u.value, radix: 16)
                if h.count < 2 { out.append("0") }
                out.append(h)
            case 0x2F where out.last == "<":  // </ → <\/ (XSS 방지)
                out.append("\\/")
            case 0x2028: out.append("\\u2028")  // LS (JS line terminator)
            case 0x2029: out.append("\\u2029")  // PS (JS line terminator)
            default: out.unicodeScalars.append(u)
            }
        }
        out.append("\"")
    }

    /// 이미 형성된 JSON 텍스트에 XSS 안전 이스케이프만 단일 패스로 적용한다.
    /// `<\/`는 유효한 JSON(슬래시는 선택적 이스케이프 가능)이므로 안전하다.
    private static func appendJSEscapedRaw(into out: inout String, _ s: String) {
        for u in s.unicodeScalars {
            switch u.value {
            case 0x2F where out.last == "<":  // </ → <\/ (XSS 방지)
                out.append("\\/")
            case 0x2028: out.append("\\u2028")
            case 0x2029: out.append("\\u2029")
            default: out.unicodeScalars.append(u)
            }
        }
    }
}
internal struct KSAnyEncodable: Encodable {
    let base: any Encodable
    init(_ base: any Encodable) { self.base = base }
    func encode(to encoder: any Encoder) throws {
        // Codable 프로토콜 — untyped throws (변경 불가)
        try base.encode(to: encoder)
    }
}
