internal import Foundation

/// 한 WebView 인스턴스에 적용된 preference / 플랫폼 옵션의 결과 보고.
///
/// 각 호스트(Win/macOS/Linux PAL)의 webview 초기화 단계에서 채워지며,
/// IPC 명령 `__ks.webview.capabilities()` 또는 호스트 직접 접근으로 조회된다.
/// 일관된 키로 보고하므로 프론트엔드에서 OS와 무관하게 같은 키로 결과를
/// 검사할 수 있다.
///
/// 가능한 상태:
/// - `applied`: 호스트에 성공적으로 적용됨.
/// - `unsupported`: 현재 플랫폼/런타임에서 지원하지 않음 (조용히 무시됨).
/// - `error(message)`: 적용 시도 중 비치명적 오류 발생.
public final class KSWebViewCapabilityReport: @unchecked Sendable {
    public enum Status: Sendable, Equatable {
        case applied
        case unsupported
        case error(String)
    }

    private let lock = NSLock()
    private var entries: [String: Status] = [:]

    public init() {}

    public func record(_ key: String, _ status: Status) {
        lock.lock()
        defer { lock.unlock() }
        entries[key] = status
    }

    public func snapshot() -> [String: Status] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// JSON 직렬화용 평면 표현. status는 `applied|unsupported|error` 문자열로,
    /// error의 경우 `errorMessage` 필드에 메시지가 별도로 노출된다.
    public func jsonRepresentation() -> [String: [String: String]] {
        lock.lock()
        defer { lock.unlock() }
        var out: [String: [String: String]] = [:]
        for (key, status) in entries {
            switch status {
            case .applied:
                out[key] = ["status": "applied"]
            case .unsupported:
                out[key] = ["status": "unsupported"]
            case .error(let msg):
                out[key] = ["status": "error", "errorMessage": msg]
            }
        }
        return out
    }
}
