#if os(iOS)
    public import KalsaeCore
    internal import Security
    internal import Foundation

    /// iOS Keychain Services 기반 `KSCredentialBackend` 구현체입니다.
    ///
    /// Apple 플랫폼의 키체인(Keychain)을 사용하여 자격 증명(비밀번호, 토큰 등)을
    /// 안전하게 저장합니다. iOS에서는 앱이 샌드박스 내에서 실행되므로, 키체인이
    /// 유일한 안전한 영구 저장소입니다.
    ///
    /// macOS 버전과 동일한 방식으로 동작하지만, iOS는 항상 디바이스가 첫
    /// 잠금 해제된 후에 키체인에 접근할 수 있습니다. 백그라운드 작업과의
    /// 호환성을 위해 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 접근
    /// 수준을 사용합니다. 이는 디바이스가 부팅 후 처음으로 잠금 해제되면
    /// 앱이 백그라운드에 있더라도 키체인 항목에 접근할 수 있음을 의미합니다.
    /// `ThisDeviceOnly` 접미사는 항목이 iCloud를 통해 다른 디바이스로
    /// 동기화되지 않도록 합니다.
    public struct KSiOSCredentialBackend: KSCredentialBackend, Sendable {
        public init() {}

        /// 키체인에 자격 증명을 저장합니다. 이미 존재하는 항목은 갱신됩니다.
        /// - Parameters:
        ///   - key: 저장할 자격 증명의 키 (서비스 + 계정 식별자)
        ///   - secret: 저장할 비밀 데이터
        /// - Throws: `KSError` — 키체인 작업 실패 시 `code: .ioFailed`
        public func set(_ key: KSCredentialKey, secret: Data) async throws(KSError) {
            try Self.write(key: key, secret: secret)
        }

        /// 키체인에서 자격 증명을 읽어 반환합니다.
        /// - Parameter key: 조회할 자격 증명의 키
        /// - Returns: 저장된 비밀 데이터 (없으면 `nil`)
        /// - Throws: `KSError` — 키체인 작업 실패 시 `code: .ioFailed`
        public func get(_ key: KSCredentialKey) async throws(KSError) -> Data? {
            try Self.read(key: key)
        }

        /// 키체인에서 자격 증명을 삭제합니다.
        /// - Parameter key: 삭제할 자격 증명의 키
        /// - Throws: `KSError` — 키체인 작업 실패 시 `code: .ioFailed`
        public func delete(_ key: KSCredentialKey) async throws(KSError) {
            try Self.erase(key: key)
        }

        /// 특정 서비스에 속한 모든 자격 증명 키를 나열합니다.
        /// - Parameter service: 조회할 서비스 식별자
        /// - Returns: 해당 서비스에 저장된 모든 `KSCredentialKey` 배열
        /// - Throws: `KSError` — 키체인 작업 실패 시 `code: .ioFailed`
        public func list(service: String) async throws(KSError) -> [KSCredentialKey] {
            try Self.enumerate(service: service)
        }

        /// 주어진 키로 키체인 쿼리 사전을 생성합니다.
        /// - Parameter key: 쿼리 대상 자격 증명 키
        /// - Returns: `SecItemCopyMatching` 등에 사용할 CFDictionary 스타일 사전
        private static func baseQuery(_ key: KSCredentialKey) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: key.service,
                kSecAttrAccount as String: key.account,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            ]
        }

        /// 키체인에 항목을 쓰거나 갱신합니다. 이미 존재하면 갱신(`SecItemUpdate`),
        /// 없으면 새로 추가(`SecItemAdd`)합니다.
        private static func write(key: KSCredentialKey, secret: Data) throws(KSError) {
            var query = baseQuery(key)
            let update: [String: Any] = [
                kSecValueData as String: secret,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if updateStatus == errSecSuccess { return }
            if updateStatus == errSecItemNotFound {
                query[kSecValueData as String] = secret
                query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                let addStatus = SecItemAdd(query as CFDictionary, nil)
                if addStatus == errSecSuccess { return }
                throw Self.wrap(status: addStatus, op: "set/add")
            }
            throw Self.wrap(status: updateStatus, op: "set/update")
        }

        /// 키체인에서 항목을 조회합니다.
        /// - Returns: 저장된 `Data` (항목이 없으면 `nil`)
        private static func read(key: KSCredentialKey) throws(KSError) -> Data? {
            var query = baseQuery(key)
            query[kSecReturnData as String] = kCFBooleanTrue as Any
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            if status != errSecSuccess { throw Self.wrap(status: status, op: "get") }
            return item as? Data
        }

        /// 키체인에서 항목을 삭제합니다.
        private static func erase(key: KSCredentialKey) throws(KSError) {
            let query = baseQuery(key)
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound { return }
            throw Self.wrap(status: status, op: "delete")
        }

        /// 특정 서비스의 모든 키체인 항목을 열거합니다.
        /// - Parameter service: 서비스 식별자
        /// - Returns: 키체인에 저장된 `KSCredentialKey` 배열
        private static func enumerate(service: String) throws(KSError) -> [KSCredentialKey] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
                kSecReturnAttributes as String: kCFBooleanTrue as Any,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]
            var items: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &items)
            if status == errSecItemNotFound { return [] }
            if status != errSecSuccess { throw Self.wrap(status: status, op: "list") }
            guard let array = items as? [[String: Any]] else { return [] }
            return array.compactMap { attrs in
                guard let acct = attrs[kSecAttrAccount as String] as? String else { return nil }
                return KSCredentialKey(service: service, account: acct)
            }
        }

        /// `OSStatus`를 `KSError`로 변환합니다.
        /// - Parameters:
        ///   - status: Security framework가 반환한 상태 코드
        ///   - op: 실패한 작업의 설명 (로깅용)
        /// - Returns: 사람이 읽을 수 있는 메시지가 포함된 `KSError`
        private static func wrap(status: OSStatus, op: String) -> KSError {
            let message: String
            if let cfMsg = SecCopyErrorMessageString(status, nil) {
                message = cfMsg as String
            } else {
                message = "OSStatus \(status)"
            }
            return KSError(
                code: .ioFailed,
                message: "Keychain \(op) failed: \(message)",
                data: .int(Int(status)))
        }
    }
#endif
