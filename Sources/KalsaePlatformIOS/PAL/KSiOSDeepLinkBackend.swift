#if os(iOS)
    public import KalsaeCore
    public import Foundation

    public struct KSiOSDeepLinkBackend: KSDeepLinkBackend, Sendable {
        public let identifier: String

        public init(identifier: String) {
            self.identifier = identifier
        }

        public func register(scheme: String) throws(KSError) {
            _ = scheme
            throw KSError.unsupportedPlatform(
                "iOS URL scheme registration is Info.plist-driven and cannot be changed at runtime")
        }

        public func unregister(scheme: String) throws(KSError) {
            _ = scheme
            throw KSError.unsupportedPlatform(
                "iOS URL scheme unregistration is not available at runtime")
        }

        public func isRegistered(scheme: String) -> Bool {
            guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
                return false
            }
            let lower = scheme.lowercased()
            for entry in urlTypes {
                guard let schemes = entry["CFBundleURLSchemes"] as? [String] else { continue }
                if schemes.contains(where: { $0.lowercased() == lower }) {
                    return true
                }
            }
            return false
        }

        public func currentLaunchURLs(forSchemes schemes: [String]) -> [String] {
            let lowerSchemes = Set(schemes.map { $0.lowercased() })
            return CommandLine.arguments.filter { arg in
                guard let idx = arg.firstIndex(of: ":") else { return false }
                return lowerSchemes.contains(arg[..<idx].lowercased())
            }
        }

        public func extractURLs(fromArgs args: [String], forSchemes schemes: [String]) -> [String] {
            let lowerSchemes = Set(schemes.map { $0.lowercased() })
            return args.filter { arg in
                guard let idx = arg.firstIndex(of: ":") else { return false }
                let scheme = arg[..<idx].lowercased()
                return lowerSchemes.contains(scheme) && URL(string: arg) != nil
            }
        }
    }
#endif
