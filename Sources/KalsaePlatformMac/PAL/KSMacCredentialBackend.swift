#if os(macOS)
    public import KalsaeCore
    internal import Security
    internal import Foundation

    /// macOS Keychain Services 기반 `KSCredentialBackend` 구현.
    ///
    /// 클래스: `kSecClassGenericPassword`
    /// 동기화: 항상 디바이스 로컬 (`kSecAttrSynchronizable=false`)
    /// 접근성: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
    ///        — 첫 잠금 해제 후에 접근 가능, 다른 기기로 백업되지 않음.
    public struct KSMacCredentialBackend: KSCredentialBackend, Sendable {
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

        // MARK: - Implementation

        private static func baseQuery(_ key: KSCredentialKey) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: key.service,
                kSecAttrAccount as String: key.account,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            ]
        }

        private static func write(key: KSCredentialKey, secret: Data) throws(KSError) {
            // 동일 (service, account) 항목이 있으면 update, 없으면 add.
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
