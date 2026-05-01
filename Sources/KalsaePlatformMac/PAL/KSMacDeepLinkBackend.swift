#if os(macOS)
internal import AppKit
public import KalsaeCore
public import Foundation

/// macOS 딥링크 / 커스텀 URL 스킴 기능.
///
/// 런타임 등록은 `LSSetDefaultHandlerForURLScheme` (macOS 12+)을 사용한다.
/// 시작 시 URL 캐포는 `kAEGetURL` 이벤트에 `NSAppleEventManager`를 사용한다.
public struct KSMacDeepLinkBackend: KSDeepLinkBackend, Sendable {
    /// 앱 식별자 — URL 스킴 등록에 사용되는 번들 식별자.
    public let identifier: String
    /// 시작 이벤트에서 수집된 URL들, `installAppleEventHandler()`에 의해 채워진다.
    nonisolated(unsafe) private static var launchURLs: [String] = []
    private static var urlHandler: (@MainActor (String) -> Void)?

    public init(identifier: String) {
        self.identifier = identifier
    }

    /// `kAEGetURL` 이벤트를 캐포하려면 앱 시작 시 한 번 호출해야 한다.
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
        // 빈 문자열을 전달해 시스템 기본값으로 초기화한다.
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

    /// `NSAppleEventManager` 핸들러에 의해 호출된다.
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

/// NSObject 기반의 AppleEvent 핸들러.
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