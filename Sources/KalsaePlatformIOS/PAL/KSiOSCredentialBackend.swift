#if os(iOS)
    public import KalsaeCore
    internal import Security
    internal import Foundation

    /// iOS Keychain Services 기반 `KSCredentialBackend` 구현.
    ///
    /// macOS 변형과 동일하지만 iOS는 항상 디바이스가 첫 잠금 해제된 후에
    /// 키체인에 접근할 수 있다 (백그라운드 작업 호환을 위해
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 사용).
    public struct KSiOSCredentialBackend: KSCredentialBackend, Sendable {
        public init() {}

        public func set(_ key: KSCredentialKey, secret: Data) async throws(KSError) {
            try Self.write(key: key, secret: secret)
        }

        public func get(_ key: KSCredentialKey) async throws(KSError) -> Data? {
            try Self.read(key: key)
        }

        public func delete(_ key: KSCredentialKey) async throws(KSError) {
            try Self.erase(key: key)
        }

        public func list(service: String) async throws(KSError) -> [KSCredentialKey] {
            try Self.enumerate(service: service)
        }

        private static func baseQuery(_ key: KSCredentialKey) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: key.service,
                kSecAttrAccount as String: key.account,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            ]
        }

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

        private static func erase(key: KSCredentialKey) throws(KSError) {
            let query = baseQuery(key)
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound { return }
            throw Self.wrap(status: status, op: "delete")
        }

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
