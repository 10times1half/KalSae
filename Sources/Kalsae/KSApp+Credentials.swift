public import Foundation
public import KalsaeCore

// MARK: - 자격증명(보안 비밀) 저장소 Swift 파사드
//
// JS `__KS_.secret.*` 와 1:1 매칭되는 Swift API. 내부적으로는
// 플랫폼이 제공하는 `KSCredentialBackend` 에 위임하고, `service`
// 이름에는 호스트 측에서 `KSConfig.app.identifier` 를 prefix로
// 붙여 다른 앱과 충돌하지 않도록 격리한다.

extension KSApp {

    /// 현재 플랫폼의 자격증명 백엔드. 미지원 플랫폼(현 시점: Linux/Android)
    /// 이거나 `KSPlatform.credentials` 가 nil이면 `false`.
    nonisolated public var isCredentialStoreAvailable: Bool {
        platform.credentials != nil
    }

    /// `service / account` 키에 비밀을 저장한다.
    ///
    /// - Throws: `KSError(code: .permissionDenied)` if `secret`이 허용
    ///   리스트 외이거나 비활성화된 경우. `KSError(code: .ioFailed)`
    ///   if OS 자격증명 보관소 호출 실패.
    nonisolated public func credentialSet(
        service: String,
        account: String,
        secret: Data
    ) async throws(KSError) {
        let key = try makeKey(service: service, account: account)
        let scope = config.security.secret
        guard scope.enabled else {
            throw KSError(code: .permissionDenied, message: "secret store disabled")
        }
        guard secret.count <= scope.maxSecretBytes else {
            throw KSError(
                code: .permissionDenied,
                message: "secret exceeds maxSecretBytes (\(scope.maxSecretBytes))")
        }
        guard let backend = platform.credentials else {
            throw KSError(code: .unsupportedPlatform, message: "credentials backend unavailable")
        }
        try await backend.set(key, secret: secret)
    }

    /// 비밀을 읽어 반환한다. 키가 없으면 `nil`.
    nonisolated public func credentialGet(
        service: String,
        account: String
    ) async throws(KSError) -> Data? {
        let key = try makeKey(service: service, account: account)
        let scope = config.security.secret
        guard scope.enabled else {
            throw KSError(code: .permissionDenied, message: "secret store disabled")
        }
        guard let backend = platform.credentials else {
            throw KSError(code: .unsupportedPlatform, message: "credentials backend unavailable")
        }
        return try await backend.get(key)
    }

    /// `service / account` 키의 비밀을 삭제한다. 없으면 no-op.
    nonisolated public func credentialDelete(
        service: String,
        account: String
    ) async throws(KSError) {
        let key = try makeKey(service: service, account: account)
        let scope = config.security.secret
        guard scope.enabled, scope.allowDelete else {
            throw KSError(code: .permissionDenied, message: "delete not allowed")
        }
        guard let backend = platform.credentials else {
            throw KSError(code: .unsupportedPlatform, message: "credentials backend unavailable")
        }
        try await backend.delete(key)
    }

    /// 주어진 `service` 에 저장된 모든 account 목록을 반환한다.
    /// 결과의 `service`는 호출자가 넘긴 그대로(prefix 제거됨)이다.
    nonisolated public func credentialList(
        service: String
    ) async throws(KSError) -> [KSCredentialKey] {
        let scope = config.security.secret
        guard scope.enabled, scope.allowList else {
            throw KSError(code: .permissionDenied, message: "list not allowed")
        }
        guard scope.permits(service: service) else {
            throw KSError(code: .permissionDenied, message: "service not in allowedServices")
        }
        guard let backend = platform.credentials else {
            throw KSError(code: .unsupportedPlatform, message: "credentials backend unavailable")
        }
        let prefixed = prefixedService(service)
        let raw = try await backend.list(service: prefixed)
        // OS에는 prefix가 붙은 service로 저장되어 있지만 호출자에게는
        // 원래 이름으로 환원해서 돌려준다.
        return raw.map { KSCredentialKey(service: service, account: $0.account) }
    }

    // MARK: - 내부 헬퍼

    nonisolated private func makeKey(
        service: String,
        account: String
    ) throws(KSError) -> KSCredentialKey {
        guard !service.isEmpty, !account.isEmpty else {
            throw KSError(code: .invalidArgument, message: "service and account required")
        }
        guard config.security.secret.permits(service: service) else {
            throw KSError(code: .permissionDenied, message: "service not in allowedServices")
        }
        return KSCredentialKey(service: prefixedService(service), account: account)
    }

    nonisolated private func prefixedService(_ service: String) -> String {
        let id = config.app.identifier
        return id.isEmpty ? service : "\(id).\(service)"
    }
}
