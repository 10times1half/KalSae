/// `__ks.secret.*` 핸들러 등록 — `set`, `get`, `delete`, `list`.
///
/// 각 호출은 다음 게이트를 거친다:
///   1. `scope.enabled` 및 `scope.permits(service:)` 검사 — 실패 시 `.commandNotAllowed`.
///   2. `set`은 `scope.maxSecretBytes`를 검사 — 초과 시 `.invalidArgument`.
///   3. `service` 값에 호스트 앱의 bundleId prefix를 자동으로 적용해 다른 앱의
///      키체인 항목을 침범하지 못하게 한다.
///
/// JS 측은 `secret`/`data` 필드를 base64로 전송한다. 현재 디스패처는 인자/결과
/// 페이로드를 로깅하지 않으므로 별도의 마스킹 미들웨어는 두지 않는다 — 향후
/// 로깅 미들웨어를 도입할 경우 `__ks.secret.*` 프리픽스를 마스킹 대상으로 한다.
import Foundation

extension KSBuiltinCommands {
    struct SecretSetArg: Codable, Sendable {
        let service: String
        let account: String
        /// base64 인코딩된 시크릿 본문.
        let secret: String
    }

    struct SecretGetArg: Codable, Sendable {
        let service: String
        let account: String
    }

    struct SecretGetResult: Codable, Sendable {
        /// base64 인코딩된 시크릿 본문. 항목이 없으면 `nil`.
        let secret: String?
    }

    struct SecretDeleteArg: Codable, Sendable {
        let service: String
        let account: String
    }

    struct SecretListArg: Codable, Sendable {
        let service: String
    }

    struct SecretListItem: Codable, Sendable {
        /// JS 호출자가 넘긴 그대로의 service (bundleId prefix 제거됨).
        let service: String
        let account: String
    }

    struct SecretListResult: Codable, Sendable {
        let items: [SecretListItem]
    }

    static func registerSecretCommands(
        into registry: KSCommandRegistry,
        backend: any KSCredentialBackend,
        scope: KSSecretScope,
        bundleId: String
    ) async {
        // service 정규화: 호출자가 넘긴 짧은 이름에 bundleId prefix를 붙여
        // 다른 앱과 키체인 충돌을 막는다. `nil` 반환은 차단.
        @Sendable func normalize(service: String) throws(KSError) -> String {
            guard scope.permits(service: service) else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "secret service '\(service)' is not in scope.allowedServices.",
                    data: .string(service))
            }
            if bundleId.isEmpty { return service }
            return "\(bundleId).\(service)"
        }

        await register(registry, "__ks.secret.set") {
            (args: SecretSetArg) throws(KSError) -> Empty in
            let fullService = try normalize(service: args.service)
            guard let data = Data(base64Encoded: args.secret) else {
                throw KSError(
                    code: .invalidArgument,
                    message: "secret payload is not valid base64.")
            }
            guard data.count <= scope.maxSecretBytes else {
                throw KSError(
                    code: .invalidArgument,
                    message: "secret exceeds maxSecretBytes (\(scope.maxSecretBytes)).")
            }
            let key = KSCredentialKey(service: fullService, account: args.account)
            try await backend.set(key, secret: data)
            return Empty()
        }

        await registerQuery(registry, "__ks.secret.get") {
            (args: SecretGetArg) throws(KSError) -> SecretGetResult in
            let fullService = try normalize(service: args.service)
            let key = KSCredentialKey(service: fullService, account: args.account)
            let data = try await backend.get(key)
            return SecretGetResult(secret: data?.base64EncodedString())
        }

        await register(registry, "__ks.secret.delete") {
            (args: SecretDeleteArg) throws(KSError) -> Empty in
            guard scope.allowDelete else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "secret.delete is disabled by scope.allowDelete=false.")
            }
            let fullService = try normalize(service: args.service)
            let key = KSCredentialKey(service: fullService, account: args.account)
            try await backend.delete(key)
            return Empty()
        }

        await registerQuery(registry, "__ks.secret.list") {
            (args: SecretListArg) throws(KSError) -> SecretListResult in
            guard scope.allowList else {
                throw KSError(
                    code: .commandNotAllowed,
                    message: "secret.list is disabled by scope.allowList=false.")
            }
            let fullService = try normalize(service: args.service)
            let raw = try await backend.list(service: fullService)
            // bundleId prefix를 떼어 호출자가 넘긴 short service로 되돌린다.
            let prefix = bundleId.isEmpty ? "" : "\(bundleId)."
            let items = raw.map { key -> SecretListItem in
                var short = key.service
                if !prefix.isEmpty, short.hasPrefix(prefix) {
                    short = String(short.dropFirst(prefix.count))
                }
                return SecretListItem(service: short, account: key.account)
            }
            return SecretListResult(items: items)
        }
    }
}
