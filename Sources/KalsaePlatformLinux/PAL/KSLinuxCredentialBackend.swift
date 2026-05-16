#if os(Linux)
    public import KalsaeCore
    internal import CLibSecret
    internal import Foundation
    internal import Glibc

    /// libsecret-1 (Secret Service) 기반 `KSCredentialBackend` 구현.
    ///
    /// 저장소: 사용자 로그인 keyring (`SECRET_COLLECTION_DEFAULT`).
    /// 백엔드: D-Bus `org.freedesktop.secrets`
    /// (GNOME Keyring / KWallet shim / KeePassXC 등 어떤 구현이라도 동작).
    ///
    /// 단순성:
    /// * 콜백 없는 sync API (`secret_password_*v_sync`)만 사용.
    /// * 가변 인자 우회 — `*v_sync` 변형이 GHashTable로 attribute를 받는다.
    /// * 스키마는 BSS에 배치된 단일 정적 인스턴스 (`ks_libsecret_credential_schema`).
    ///
    /// 보안:
    /// * 시크릿 본문은 `secret_password_wipe`로 zero-on-free.
    /// * `list()`는 attribute만 추출 — value는 전송 회피.
    /// * 시크릿은 base64 인코딩 후 저장 (libsecret는 NUL-terminated C 문자열 요구).
    /// * 스키마 attributes `{service, account}` — service는 IPC 계층에서
    ///   bundleId prefix가 적용되어 앱 간 격리를 보장한다.
    public struct KSLinuxCredentialBackend: KSCredentialBackend, Sendable {
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

        // MARK: - Attribute table helpers

        /// `{service, account}` GHashTable을 생성한다.
        /// 호출자가 `g_hash_table_unref`로 해제해야 한다.
        private static func attrTable(
            service: String, account: String?
        ) -> OpaquePointer {
            let table = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free)!
            // g_strdup으로 GLib 힙에 복사 — 테이블 destroy 시 g_free로 회수.
            service.withCString { svc in
                _ = g_hash_table_insert(
                    table,
                    UnsafeMutableRawPointer(mutating: g_strdup("service")),
                    UnsafeMutableRawPointer(mutating: g_strdup(svc)))
            }
            if let account {
                account.withCString { acc in
                    _ = g_hash_table_insert(
                        table,
                        UnsafeMutableRawPointer(mutating: g_strdup("account")),
                        UnsafeMutableRawPointer(mutating: g_strdup(acc)))
                }
            }
            return table
        }

        // MARK: - Implementation

        private static func write(key: KSCredentialKey, secret: Data) throws(KSError) {
            let table = attrTable(service: key.service, account: key.account)
            defer { g_hash_table_unref(table) }

            // libsecret은 password를 NUL-terminated C 문자열로 요구한다.
            // 임의 바이너리는 base64 인코딩해 저장 (Tauri/keyring 크레이트와 동일).
            let encoded = secret.base64EncodedString()
            let label = "\(key.service) / \(key.account)"
            var gerror: UnsafeMutablePointer<GError>? = nil

            let ok = encoded.withCString { (passwordPtr: UnsafePointer<CChar>) -> Bool in
                label.withCString { (labelPtr: UnsafePointer<CChar>) in
                    secret_password_storev_sync(
                        ks_libsecret_credential_schema(),
                        table,
                        SECRET_COLLECTION_DEFAULT,
                        labelPtr,
                        passwordPtr,
                        nil, // cancellable
                        &gerror) != 0
                }
            }
            if !ok {
                throw Self.mapGError(gerror, op: "set")
            }
        }

        private static func read(key: KSCredentialKey) throws(KSError) -> Data? {
            let table = attrTable(service: key.service, account: key.account)
            defer { g_hash_table_unref(table) }

            var gerror: UnsafeMutablePointer<GError>? = nil
            let password: UnsafeMutablePointer<CChar>? = secret_password_lookupv_sync(
                ks_libsecret_credential_schema(),
                table,
                nil,
                &gerror)
            if let err = gerror {
                throw Self.mapGError(err, op: "get")
            }
            guard let password else { return nil }

            // 즉시 디코딩 후 wipe — 평문이 힙에 남지 않게 한다.
            let encoded = String(cString: password)
            secret_password_wipe(password)
            if let data = Data(base64Encoded: encoded) {
                return data
            }
            // 외부 도구가 비-base64 평문을 저장한 경우 fallback (UTF-8 바이트).
            return Data(encoded.utf8)
        }

        private static func erase(key: KSCredentialKey) throws(KSError) {
            let table = attrTable(service: key.service, account: key.account)
            defer { g_hash_table_unref(table) }

            var gerror: UnsafeMutablePointer<GError>? = nil
            // 매칭 없음 → FALSE 반환·error=NULL → macOS/Windows와 동일하게 noop.
            _ = secret_password_clearv_sync(
                ks_libsecret_credential_schema(),
                table,
                nil,
                &gerror)
            if let err = gerror {
                throw Self.mapGError(err, op: "delete")
            }
        }

        private static func enumerate(service: String) throws(KSError) -> [KSCredentialKey] {
            // service만 매칭 (account 미지정) — 모든 항목 열거.
            let table = attrTable(service: service, account: nil)
            defer { g_hash_table_unref(table) }

            var gerror: UnsafeMutablePointer<GError>? = nil
            let listPtr: UnsafeMutablePointer<GList>? = secret_password_searchv_sync(
                ks_libsecret_credential_schema(),
                table,
                SECRET_SEARCH_ALL,
                nil,
                &gerror)
            if let err = gerror {
                throw Self.mapGError(err, op: "list")
            }
            guard let head = listPtr else { return [] }
            defer { g_list_free_full(head, _ksLinuxCredentialFreeItem) }

            var out: [KSCredentialKey] = []
            var cursor: UnsafeMutablePointer<GList>? = head
            while let node = cursor {
                if let data = node.pointee.data {
                    let retrievable = OpaquePointer(data)
                    if let attrs = secret_retrievable_get_attributes(retrievable) {
                        defer { g_hash_table_unref(attrs) }
                        let acctRaw = "account".withCString { keyPtr in
                            g_hash_table_lookup(attrs, keyPtr)
                        }
                        if let acctRaw {
                            let account = String(
                                cString: acctRaw.assumingMemoryBound(to: CChar.self))
                            out.append(KSCredentialKey(service: service, account: account))
                        }
                    }
                }
                cursor = node.pointee.next
            }
            return out
        }

        // MARK: - GError mapping

        private static func mapGError(
            _ err: UnsafeMutablePointer<GError>?, op: String
        ) -> KSError {
            guard let err else {
                return KSError(
                    code: .ioFailed,
                    message: "libsecret \(op) failed (no GError)")
            }
            defer { g_error_free(err) }
            let domain = err.pointee.domain
            let code = err.pointee.code
            let message =
                err.pointee.message.map { String(cString: $0) } ?? "unknown libsecret error"

            // Secret Service 가용성 판정: D-Bus 서비스가 활성화되지 않은
            // 환경(헤드리스 CI / WSL / 컨테이너 등) → unsupportedPlatform.
            // glib `g_dbus_error_quark()` 도메인 + 표준 오류 코드 비교.
            if domain == g_dbus_error_quark() {
                // G_DBUS_ERROR_SERVICE_UNKNOWN = 35,
                // G_DBUS_ERROR_NAME_HAS_NO_OWNER = 36,
                // G_DBUS_ERROR_NOT_SUPPORTED = 39
                if code == 35 || code == 36 || code == 39 {
                    return KSError(
                        code: .unsupportedPlatform,
                        message:
                            "Secret Service not available on this host: \(message)")
                }
            }
            return KSError(
                code: .ioFailed,
                message: "libsecret \(op) failed: \(message)",
                data: .int(Int(code)))
        }
    }

    // GList 노드 해제 콜백: 각 요소는 GObject(SecretRetrievable) → g_object_unref.
    // `@convention(c)` 호환을 위해 파일 스코프 전역 함수로 정의한다.
    private func _ksLinuxCredentialFreeItem(_ ptr: gpointer?) {
        guard let ptr else { return }
        g_object_unref(ptr)
    }
#endif
