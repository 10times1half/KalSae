import Foundation

extension KSBuiltinCommands {
    struct DeepLinkSchemeArg: Codable, Sendable {
        let scheme: String
    }
    struct DeepLinkBoolResult: Codable, Sendable {
        let value: Bool
    }
    struct DeepLinkURLsResult: Codable, Sendable {
        let urls: [String]
    }

    /// `__ks.deepLink.*` 명령을 등록한다. 설정된 `schemes` 목록은
    /// `register`/`unregister`/`isRegistered`를 게이팅한다: 호출자는
    /// 구성에 없는 스킴을 등록할 수 없다(`commandNotAllowed`).
    ///
    /// `currentLaunchURLs`는 현재 프로세스가 시작될 때 전달된 URL을
    /// 반환한다(첫 실행 후 이후 `relayed` 인스턴스가 인자를 전달하는
    /// 경우도 포함). 새 URL이 도착하면 호스트가 `__ks.deepLink.openURL`
    /// 이벤트를 방출할 책임이 있다.
    static func registerDeepLinkCommands(
        into registry: KSCommandRegistry,
        backend: any KSDeepLinkBackend,
        config: KSDeepLinkConfig
    ) async {
        let allowedSchemes = Set(config.schemes.map { $0.lowercased() })

        @Sendable func gate(_ scheme: String) throws(KSError) {
            guard allowedSchemes.contains(scheme.lowercased()) else {
                throw KSError(code: .commandNotAllowed,
                    message: "deepLink scheme '\(scheme)' is not declared in config.deepLink.schemes",
                    data: .string(scheme))
            }
        }

        await register(registry, "__ks.deepLink.register") { (args: DeepLinkSchemeArg) throws(KSError) -> Empty in
            try gate(args.scheme)
            try backend.register(scheme: args.scheme)
            return Empty()
        }
        await register(registry, "__ks.deepLink.unregister") { (args: DeepLinkSchemeArg) throws(KSError) -> Empty in
            try gate(args.scheme)
            try backend.unregister(scheme: args.scheme)
            return Empty()
        }
        await registerQuery(registry, "__ks.deepLink.isRegistered") { (args: DeepLinkSchemeArg) throws(KSError) -> DeepLinkBoolResult in
            try gate(args.scheme)
            return DeepLinkBoolResult(value: backend.isRegistered(scheme: args.scheme))
        }
        await registerQuery(registry, "__ks.deepLink.currentLaunchURLs") { (_: Empty) throws(KSError) -> DeepLinkURLsResult in
            DeepLinkURLsResult(urls: backend.currentLaunchURLs(forSchemes: config.schemes))
        }
    }
}
