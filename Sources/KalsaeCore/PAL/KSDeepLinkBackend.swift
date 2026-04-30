public import Foundation

/// PAL contract for the deep-link / custom URL scheme feature.
///
/// Implementations register `<scheme>://` URLs with the OS so that
/// invoking such a URL from a browser or another app launches (or
/// reuses) this app. Together with `KSApp.singleInstance`, the URL is
/// forwarded to the primary instance and surfaces in JS as a
/// `__ks.deepLink.openURL` event.
///
/// - Windows: writes `HKCU\Software\Classes\<scheme>` (per-user, no
///   admin rights). The default ProgID is `<identifier>.<scheme>`.
/// - macOS  : reserved (declared in `Info.plist`'s
///   `CFBundleURLTypes` — handled at bundle build time, not at runtime).
/// - Linux  : reserved (XDG `.desktop` MimeType association).
public protocol KSDeepLinkBackend: Sendable {
    /// Registers `scheme` with the OS so external invocations of
    /// `<scheme>://...` are routed to this executable. Idempotent.
    func register(scheme: String) throws(KSError) -> Void

    /// Removes the registry entry for `scheme`. Idempotent — a missing
    /// entry is treated as success.
    func unregister(scheme: String) throws(KSError) -> Void

    /// Returns `true` when `scheme` is currently registered to point at
    /// this executable (string match on the `shell\open\command` value).
    func isRegistered(scheme: String) -> Bool

    /// Returns every URL passed on the current process's command line
    /// whose scheme is in `schemes`. Used at startup to surface launch
    /// URLs to the page the same way as relayed second-instance URLs.
    func currentLaunchURLs(forSchemes schemes: [String]) -> [String]

    /// Filters arguments relayed from a second instance, returning only
    /// those that look like deep-link URLs whose scheme is in `schemes`.
    func extractURLs(fromArgs args: [String], forSchemes schemes: [String]) -> [String]
}
