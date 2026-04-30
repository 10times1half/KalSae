import Foundation

/// Optional autostart configuration. Mirrors Tauri's `plugin-autostart`.
///
/// When this section is present, `__ks.autostart.*` JS commands operate
/// on the OS-level "launch on login" registry entry whose name is
/// derived from `app.identifier`.
///
/// Windows: writes/reads
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\<identifier>`.
/// macOS / Linux: future. The config still parses and JS can call the
/// commands, which return `false` for `isEnabled` and throw
/// `unsupportedPlatform` for `enable`/`disable` until those PALs ship.
public struct KSAutostartConfig: Codable, Sendable, Equatable {
    /// Extra command-line arguments appended to the registered EXE
    /// invocation. Useful so the autostarted process knows it was
    /// launched by the OS rather than by the user.
    public var args: [String]

    public init(args: [String] = []) {
        self.args = args
    }

    private enum CodingKeys: String, CodingKey { case args }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
    }
}

/// Optional deep-link configuration. Mirrors Tauri's `plugin-deep-link`.
///
/// Schemes listed here can be registered with the OS so that
/// `<scheme>://...` URLs invoked from a browser or other application
/// are forwarded to this app. When a second instance is launched with
/// such a URL, `KSApp.singleInstance` relays the URL to the primary
/// instance and `__ks.deepLink.openURL` is emitted as a JS event.
public struct KSDeepLinkConfig: Codable, Sendable, Equatable {
    /// URL schemes to claim, e.g. `["myapp", "myapp-dev"]`. Schemes are
    /// case-folded to lowercase. RFC 3986 forbids `:` and `/` in the
    /// scheme; Kalsae rejects schemes containing those characters at
    /// register time.
    public var schemes: [String]
    /// When `true`, `KSApp.boot` registers every scheme with the OS on
    /// first launch (idempotent). When `false`, registration must be
    /// performed explicitly via `__ks.deepLink.register` from JS or
    /// the host's installer.
    public var autoRegisterOnLaunch: Bool

    public init(schemes: [String] = [], autoRegisterOnLaunch: Bool = false) {
        self.schemes = schemes
        self.autoRegisterOnLaunch = autoRegisterOnLaunch
    }

    private enum CodingKeys: String, CodingKey {
        case schemes, autoRegisterOnLaunch
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemes = try c.decodeIfPresent([String].self, forKey: .schemes) ?? []
        self.autoRegisterOnLaunch = try c.decodeIfPresent(
            Bool.self, forKey: .autoRegisterOnLaunch) ?? false
    }
}
