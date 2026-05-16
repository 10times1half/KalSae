#if os(Windows)
    internal import WinSDK
    public import KalsaeCore
    public import Foundation

    /// Windows Credential Manager 기반 `KSCredentialBackend` 구현.
    ///
    /// `CredWriteW` / `CredReadW` / `CredDeleteW` / `CredEnumerateW`
    /// (`advapi32.dll`)를 사용한다. 저장 위치는 사용자 자격증명 보관소
    /// (`CRED_PERSIST_LOCAL_MACHINE` 대신 `CRED_PERSIST_ENTERPRISE`를
    /// 쓰지 않음 — 로컬 사용자 잠금).
    ///
    /// `KSCredentialKey.service` 와 `account` 를 결합해
    /// `<service>/<account>` 라는 TargetName 한 줄 문자열로 인코딩한다.
    /// `service` 는 호스트가 bundleId prefix 를 미리 적용했음을 가정한다.
    public struct KSWindowsCredentialBackend: KSCredentialBackend, Sendable {
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

        // MARK: - TargetName encoding

        /// `(service, account)` → `"<service>/<account>"`.
        private static func targetName(_ key: KSCredentialKey) -> String {
            "\(key.service)/\(key.account)"
        }

        private static func splitTarget(_ target: String, expectedService: String) -> KSCredentialKey? {
            let prefix = expectedService + "/"
            guard target.hasPrefix(prefix) else { return nil }
            let account = String(target.dropFirst(prefix.count))
            return KSCredentialKey(service: expectedService, account: account)
        }

        // MARK: - Win32

        private static func write(key: KSCredentialKey, secret: Data) throws(KSError) {
            let target = targetName(key)
            let blobLen = DWORD(secret.count)
            let result: Bool = target.withUTF16Pointer { targetPtr in
                key.account.withUTF16Pointer { userPtr in
                    secret.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
                        let blobPtr = UnsafeMutablePointer<BYTE>(
                            mutating: raw.bindMemory(to: BYTE.self).baseAddress)
                        var cred = CREDENTIALW()
                        cred.Flags = 0
                        cred.Type = DWORD(CRED_TYPE_GENERIC)
                        cred.TargetName = UnsafeMutablePointer(mutating: targetPtr)
                        cred.Comment = nil
                        cred.LastWritten = FILETIME()
                        cred.CredentialBlobSize = blobLen
                        cred.CredentialBlob = blobPtr
                        cred.Persist = DWORD(CRED_PERSIST_LOCAL_MACHINE)
                        cred.AttributeCount = 0
                        cred.Attributes = nil
                        cred.TargetAlias = nil
                        cred.UserName = UnsafeMutablePointer(mutating: userPtr)
                        return CredWriteW(&cred, 0)
                    }
                }
            }
            if !result {
                let err = GetLastError()
                throw KSError(
                    code: .ioFailed,
                    message: "CredWriteW failed (\(err))",
                    data: .int(Int(err)))
            }
        }

        private static func read(key: KSCredentialKey) throws(KSError) -> Data? {
            let target = targetName(key)
            var credPtr: PCREDENTIALW? = nil
            let ok: Bool = target.withUTF16Pointer { targetPtr in
                CredReadW(targetPtr, DWORD(CRED_TYPE_GENERIC), 0, &credPtr)
            }
            if !ok {
                let err = GetLastError()
                if err == ERROR_NOT_FOUND { return nil }
                throw KSError(
                    code: .ioFailed,
                    message: "CredReadW failed (\(err))",
                    data: .int(Int(err)))
            }
            guard let cred = credPtr else { return nil }
            defer { CredFree(cred) }
            let count = Int(cred.pointee.CredentialBlobSize)
            guard count > 0, let blob = cred.pointee.CredentialBlob else { return Data() }
            return Data(bytes: blob, count: count)
        }

        private static func erase(key: KSCredentialKey) throws(KSError) {
            let target = targetName(key)
            let ok: Bool = target.withUTF16Pointer { targetPtr in
                CredDeleteW(targetPtr, DWORD(CRED_TYPE_GENERIC), 0)
            }
            if !ok {
                let err = GetLastError()
                if err == ERROR_NOT_FOUND { return }
                throw KSError(
                    code: .ioFailed,
                    message: "CredDeleteW failed (\(err))",
                    data: .int(Int(err)))
            }
        }

        private static func enumerate(service: String) throws(KSError) -> [KSCredentialKey] {
            // CredEnumerateW의 필터는 와일드카드를 허용한다: `<service>/*`
            let filter = "\(service)/*"
            var count: DWORD = 0
            var items: UnsafeMutablePointer<PCREDENTIALW?>? = nil
            let ok: Bool = filter.withUTF16Pointer { filterPtr in
                CredEnumerateW(filterPtr, 0, &count, &items)
            }
            if !ok {
                let err = GetLastError()
                if err == ERROR_NOT_FOUND { return [] }
                throw KSError(
                    code: .ioFailed,
                    message: "CredEnumerateW failed (\(err))",
                    data: .int(Int(err)))
            }
            defer { if let items { CredFree(items) } }
            guard let items, count > 0 else { return [] }
            var out: [KSCredentialKey] = []
            out.reserveCapacity(Int(count))
            for i in 0..<Int(count) {
                guard let cred = items[i] else { continue }
                guard let targetPtr = cred.pointee.TargetName else { continue }
                let target = UnsafePointer(targetPtr).toString()
                if let key = splitTarget(target, expectedService: service) {
                    out.append(key)
                }
            }
            return out
        }
    }
#endif
