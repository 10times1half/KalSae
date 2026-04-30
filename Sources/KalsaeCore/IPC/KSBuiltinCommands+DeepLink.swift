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

    /// Registers `__ks.deepLink.*` commands. The configured `schemes`
    /// list gates `register`/`unregister`/`isRegistered`: callers cannot
    /// register schemes that are not in the config (`commandNotAllowed`).
    ///
    /// `currentLaunchURLs` returns the URLs that the current process
    /// was launched with (after first-run + subsequent `relayed`
    /// instances forward their args). The host is responsible for
    /// emitting `__ks.deepLink.openURL` events when new URLs arrive.
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
