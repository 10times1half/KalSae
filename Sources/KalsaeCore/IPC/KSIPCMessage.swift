/// 네이티브 webview 브리지를 통해 Swift와 JS 간에 교환되는 와이어 수준 봉투.
///
/// 형식은 의도적으로 Tauri의 v2 IPC를 미러링하여 등록된 명령에서 생성된
/// TypeScript 타입이 인체공학적으로 유지되도록 한다.
public import Foundation

public struct KSIPCMessage: Codable, Sendable, Equatable {
    /// 봉투의 나머지 부분이 어떻게 해석될지 선택하는 판별자.
    public enum Kind: String, Codable, Sendable {
        /// JS → Swift: 등록된 `@KSCommand` 호출.
        case invoke
        /// Swift → JS: 이전 `invoke`에 대한 응답.
        case response
        /// Swift → JS 또는 JS → Swift: 발사 후 망각 이벤트.
        case event
    }

    /// `Kind` 참조 — `payload`/`isError`가 어떻게 해석될지 선택한다.
    public var kind: Kind
    /// `invoke`를 `response`와 연결한다. 해당 종류에는 필수이며,
    /// `event`에서는 무시된다.
    public var id: String?
    /// `invoke`의 명령 이름, `event`의 이벤트 이름.
    public var name: String?
    /// JSON 인코딩된 페이로드. `invoke`: 인자. `response`:
    /// 반환값 또는 `KSError`. `event`: 페이로드.
    public var payload: Data?
    /// `true`일 때 `payload`가 `KSError`를 인코딩한다.
    public var isError: Bool?

    public init(
        kind: Kind,
        id: String? = nil,
        name: String? = nil,
        payload: Data? = nil,
        isError: Bool? = nil
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.payload = payload
        self.isError = isError
    }
}
