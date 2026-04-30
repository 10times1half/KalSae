#if os(macOS)
internal import AppKit
public import KalsaeCore
public import Foundation

/// macOS deep-link / custom URL scheme feature.
///
/// Runtime registration uses `LSSetDefaultHandlerForURLScheme` (macOS 12+).
/// Launch-time URL capture uses `NSAppleEventManager` for `kAEGetURL` events.
public struct KSMacDeepLinkBackend: KSDeepLinkBackend, Sendable {
    /// App identifier — used as the bundle identifier for URL scheme registration.
    public let identifier: String
    /// Collected URLs from launch events, filled by `installAppleEventHandler()`.
    nonisolated(unsafe) private static var launchURLs: [String] = []
    private static var urlHandler: (@MainActor (String) -> Void)?

    public init(identifier: String) {
        self.identifier = identifier
    }

    /// Must be called once at app startup to capture `kAEGetURL` events.
    @MainActor
    public static func installAppleEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            NSApp,
            andSelector: #selector(KSMacAppleEventRouter.handleGetURLEvent(_:with:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    public func register(scheme: String) throws(KSError) {
        guard #available(macOS 12.0, *) else {
            throw KSError(code: .unsupportedPlatform,
                          message: "Deep link registration requires macOS 12+")
        }
        let s = try normalizeSchema(scheme)
        LSSetDefaultHandlerForURLScheme(s as CFString, identifier as CFString)
    }

    public func unregister(scheme: String) throws(KSError) {
        guard #available(macOS 12.0, *) else {
            throw KSError(code: .unsupportedPlatform,
                          message: "Deep link unregistration requires macOS 12+")
        }
        let s = try normalizeSchema(scheme)
        // Reset to system default by passing empty string.
        LSSetDefaultHandlerForURLScheme(s as CFString, "" as CFString)
    }

    public func isRegistered(scheme: String) -> Bool {
        guard #available(macOS 12.0, *) else { return false }
        guard let s = try? normalizeSchema(scheme),
              let handler = LSCopyDefaultHandlerForURLScheme(s as CFString)?.takeRetainedValue() as String?
        else { return false }
        return handler == identifier
    }

    public func currentLaunchURLs(forSchemes schemes: [String]) -> [String] {
        let lowerSchemes = Set(schemes.map { $0.lowercased() })
        return Self.launchURLs.filter { url in
            guard let colon = url.firstIndex(of: ":") else { return false }
            return lowerSchemes.contains(url[..<colon].lowercased())
        }
    }

    public func extractURLs(fromArgs args: [String], forSchemes schemes: [String]) -> [String] {
        let lowerSchemes = Set(schemes.map { $0.lowercased() })
        return args.filter { a in
            guard let colon = a.firstIndex(of: ":") else { return false }
            let scheme = a[..<colon].lowercased()
            return lowerSchemes.contains(scheme) && URL(string: a) != nil
        }
    }

    /// Called by `NSAppleEventManager` handler.
    public static func addLaunchURL(_ url: String) {
        launchURLs.append(url)
    }

    private func normalizeSchema(_ scheme: String) throws(KSError) -> String {
        let s = scheme.lowercased()
        guard let first = s.first, first.isLetter else {
            throw KSError(code: .invalidArgument,
                          message: "deep-link scheme must start with a letter")
        }
        return s
    }
}

/// NSObject-based AppleEvent handler.
@MainActor
internal final class KSMacAppleEventRouter: NSObject {
    @objc static func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                         with reply: NSAppleEventDescriptor) {
        guard let desc = event.paramDescriptor(forKeyword: keyDirectObject),
              let urlString = desc.stringValue
        else { return }
        KSMacDeepLinkBackend.addLaunchURL(urlString)
    }
}
#endif