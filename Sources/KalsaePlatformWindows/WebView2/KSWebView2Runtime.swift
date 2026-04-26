#if os(Windows)
import Foundation
internal import WinSDK
internal import CKalsaeWV2

/// Loads `kalsae.runtime.json` (placed next to the application executable
/// at packaging time) and decides which paths to pass to
/// `CreateCoreWebView2EnvironmentWithOptions`.
///
/// Schema (all fields optional):
/// ```json
/// {
///   "policy": "evergreen" | "fixed" | "auto",
///   "browserExecutableFolder": "webview2-runtime",  // relative or absolute
///   "userDataFolder": "%LOCALAPPDATA%/<id>/WebView2"
/// }
/// ```
internal enum KSWebView2Runtime {
    struct Policy: Codable, Sendable {
        var policy: String?
        var browserExecutableFolder: String?
        var userDataFolder: String?
    }

    /// Resolved paths suitable for handing to `KSWV2_CreateEnvironment`.
    /// `nil` means "let WebView2 pick the default".
    struct Resolved {
        var browserExecutableFolder: String?
        var userDataFolder: String?
    }

    /// Resolves runtime paths based on the runtime policy file (if any).
    /// Always returns a value; missing/invalid files yield default
    /// (Evergreen / WebView2 default user-data folder).
    static func resolve(executableDir: URL, identifier: String) -> Resolved {
        let policy = loadPolicy(executableDir: executableDir)
        let policyName = (policy?.policy ?? "evergreen").lowercased()

        var browserDir: String? = nil
        var userDataDir: String? = nil

        // 브라우저 실행 폴더: `fixed`나, 시스템에 Evergreen 런타임이 없을 때의
        // `auto`에서만 설정한다.
        if policyName == "fixed"
            || (policyName == "auto" && !isEvergreenAvailable()) {
            if let raw = policy?.browserExecutableFolder {
                let resolved = expand(raw, base: executableDir)
                if FileManager.default.fileExists(atPath: resolved) {
                    browserDir = resolved
                }
            }
        }

        // 사용자 데이터 폴더. 여러 Kalsae 앱이 프로파일을 공유하지 않도록
        // 기본값은 %LOCALAPPDATA%/<identifier>/WebView2.
        if let raw = policy?.userDataFolder {
            userDataDir = expand(raw, base: executableDir)
        } else if let local = ProcessInfo.processInfo
                    .environment["LOCALAPPDATA"] {
            userDataDir = (local as NSString)
                .appendingPathComponent(identifier)
                + "\\WebView2"
        }

        return Resolved(
            browserExecutableFolder: browserDir,
            userDataFolder: userDataDir)
    }

    // MARK: - Internals

    private static func loadPolicy(executableDir: URL) -> Policy? {
        let url = executableDir
            .appendingPathComponent("kalsae.runtime.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Policy.self, from: data)
    }

    /// Expands `%VAR%` Windows-style env tokens and resolves relative paths
    /// against `base`.
    private static func expand(_ s: String, base: URL) -> String {
        var s = s
        let env = ProcessInfo.processInfo.environment
        // %VAR% 토큰 치환.
        while let open = s.firstIndex(of: "%") {
            let after = s.index(after: open)
            guard let close = s[after...].firstIndex(of: "%") else { break }
            let name = String(s[after..<close])
            let replacement = env[name] ?? ""
            s.replaceSubrange(open...close, with: replacement)
        }
        // 아직 상대 경로면 실행 파일 디렉터리 기준으로 해석한다.
        if !s.isEmpty,
           !(s.hasPrefix("\\") || s.hasPrefix("/"))
           && !(s.count >= 2 && s[s.index(s.startIndex, offsetBy: 1)] == ":") {
            return base.appendingPathComponent(s).path
        }
        return s
    }

    /// True when `GetAvailableCoreWebView2BrowserVersionString(NULL, &v)`
    /// succeeds — i.e. the Evergreen runtime (or the user-installed
    /// Edge runtime) is available system-wide.
    private static func isEvergreenAvailable() -> Bool {
        var version: UnsafeMutablePointer<UInt16>? = nil
        let hr = KSWV2_GetAvailableBrowserVersion(nil, &version)
        if let v = version {
            CoTaskMemFree(UnsafeMutableRawPointer(v))
        }
        return hr == 0
    }
}
#endif
