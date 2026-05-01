#if os(Android)
public import KalsaeCore
public import Foundation

/// Android deep-link backend.
///
/// Scheme registration on Android is AndroidManifest.xml–driven and cannot
/// be changed at runtime — the same constraint as iOS. This backend provides
/// pure-Swift URL extraction from process arguments (for cases where the
/// Activity forwards its `Intent` URL as an argv), and exposes an injectable
/// handler for reading the launch Intent URL supplied by the JNI host.
public struct KSAndroidDeepLinkBackend: KSDeepLinkBackend, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    /// Cannot change intent-filter entries at runtime.
    public func register(scheme: String) throws(KSError) {
        _ = scheme
        throw KSError.unsupportedPlatform(
            "Android URL scheme registration is AndroidManifest-driven and cannot be changed at runtime")
    }

    /// Cannot remove intent-filter entries at runtime.
    public func unregister(scheme: String) throws(KSError) {
        _ = scheme
        throw KSError.unsupportedPlatform(
            "Android URL scheme unregistration is not available at runtime")
    }

    /// Checks whether the scheme appears in the known list passed from the
    /// JNI host (via `KSAndroidDeepLinkBackend.knownSchemes`). Defaults to
    /// `false` when the list is empty.
    public func isRegistered(scheme: String) -> Bool {
        let lower = scheme.lowercased()
        return KSAndroidDeepLinkBackend.knownSchemes.contains(lower)
    }

    /// Returns any deep-link URLs from `CommandLine.arguments` matching the
    /// given schemes. The Activity host may forward the Intent URI as the
    /// first process argument.
    public func currentLaunchURLs(forSchemes schemes: [String]) -> [String] {
        extractURLs(fromArgs: CommandLine.arguments, forSchemes: schemes)
    }

    /// Extracts well-formed URLs whose scheme is in `schemes` from `args`.
    public func extractURLs(fromArgs args: [String], forSchemes schemes: [String]) -> [String] {
        let lowerSchemes = Set(schemes.map { $0.lowercased() })
        return args.filter { arg in
            guard let idx = arg.firstIndex(of: ":") else { return false }
            let scheme = arg[..<idx].lowercased()
            return lowerSchemes.contains(scheme) && URL(string: arg) != nil
        }
    }

    // MARK: - Runtime scheme registry (populated by JNI host)

    /// Scheme names known to be declared in AndroidManifest.xml.
    /// Set this from the JNI host at startup so `isRegistered` can
    /// answer correctly without a JNI call per query.
    public nonisolated(unsafe) static var knownSchemes: Set<String> = []
}
#endif
