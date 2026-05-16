/// OS 보안 저장소(자격증명/토큰/API 키)에 대한 PAL 계약.
///
/// 각 플랫폼은 자체 보안 저장소를 사용한다:
///   * macOS / iOS : Security.framework (`SecItem*`, `kSecClassGenericPassword`)
///   * Windows     : Credential Manager (`CredWriteW` / `CredReadW`)
///   * Linux       : libsecret (Secret Service, GNOME Keyring / KWallet 등)
///   * Android     : AndroidKeyStore + AES/GCM (JNI 브리지)
///
/// 시크릿 본문은 임의의 `Data`로 다루며, 문자열 인코딩은 호출자 책임이다
/// (UTF-8 인코딩 권장). 백엔드는 키체인 환경이 없거나 비활성화된 경우
/// `KSError(.unsupportedPlatform)`을 던진다.
public import Foundation

/// `(service, account)` 쌍으로 구성되는 시크릿 식별 키.
///
/// `service`는 일반적으로 앱 식별자 prefix를 갖는다 (예: `"dev.example.app.github"`).
/// 빌트인 IPC 레이어가 자동으로 bundleId prefix를 강제하므로 PAL 구현은
/// 받은 값을 그대로 사용하면 된다.
public struct KSCredentialKey: Hashable, Sendable, Codable {
    public let service: String
    public let account: String
    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}

/// OS 시크릿 저장소 백엔드.
///
/// 모든 메서드는 비동기로 정의되어 있어 구현이 UI/메인 스레드로 홉하거나
/// 동기 OS API를 백그라운드 큐에 위임할 수 있다.
public protocol KSCredentialBackend: Sendable {
    /// `key`에 시크릿을 저장한다. 기존 값이 있으면 덮어쓴다.
    func set(_ key: KSCredentialKey, secret: Data) async throws(KSError)

    /// `key`에 저장된 시크릿을 읽는다. 존재하지 않으면 `nil`.
    func get(_ key: KSCredentialKey) async throws(KSError) -> Data?

    /// `key`에 저장된 시크릿을 삭제한다. 존재하지 않아도 오류가 아니다.
    func delete(_ key: KSCredentialKey) async throws(KSError)

    /// 주어진 `service`에 속한 모든 account 키를 나열한다.
    /// 시크릿 본문은 반환하지 않는다.
    func list(service: String) async throws(KSError) -> [KSCredentialKey]
}

extension KSCredentialBackend {
    @inline(__always)
    private func _unsupportedThrow(_ op: String) throws(KSError) -> Never {
        throw KSError(
            code: .unsupportedPlatform,
            message: "KSCredentialBackend.\(op) is not implemented on this platform.")
    }

    public func set(_ key: KSCredentialKey, secret: Data) async throws(KSError) {
        try _unsupportedThrow("set")
    }
    public func get(_ key: KSCredentialKey) async throws(KSError) -> Data? {
        try _unsupportedThrow("get")
    }
    public func delete(_ key: KSCredentialKey) async throws(KSError) {
        try _unsupportedThrow("delete")
    }
    public func list(service: String) async throws(KSError) -> [KSCredentialKey] {
        try _unsupportedThrow("list")
    }
}
