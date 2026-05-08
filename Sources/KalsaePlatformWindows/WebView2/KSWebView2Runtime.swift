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
                || (policyName == "auto" && !isEvergreenAvailable())
            {
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
                .environment["LOCALAPPDATA"], !local.isEmpty
            {
                userDataDir =
                    (local as NSString)
                    .appendingPathComponent(identifier)
                    + "\\WebView2"
            }

            // 안전망: WebView2 SDK 는 `userDataFolder == nil` 일 때 EXE 옆
            // `<exeName>.WebView2` 에 데이터를 만든다. `swift run` 으로 EXE 가
            // `.build/<triple>/debug/` 에서 실행되면 자식 `msedgewebview2.exe`
            // 들이 그 폴더에 핸들을 유지해 `.build/` 가 잠겨 빌드 산출물을
            // 지울 수 없게 된다. nil/빈 문자열, 또는 실행 파일이 위치한
            // `.build/` 트리 안쪽으로 해석된 경우 항상 `%TEMP%/Kalsae/<id>/WebView2`
            // 로 강제한다.
            if userDataDir == nil
                || userDataDir?.isEmpty == true
                || isInsideBuildTree(path: userDataDir!, executableDir: executableDir)
            {
                userDataDir = fallbackUserDataDir(identifier: identifier)
            }

            return Resolved(
                browserExecutableFolder: browserDir,
                userDataFolder: userDataDir)
        }

        // MARK: - Internals

        /// True if `path` is `.build/` 또는 그 하위에 위치하는지 검사한다.
        /// 대소문자 구분 없이, 경로 구분자(`/`/`\`) 차이를 정규화해 비교한다.
        internal static func isInsideBuildTree(path: String, executableDir: URL) -> Bool {
            // 실행 파일 경로에서 `.build` 세그먼트 위치를 찾고, `userDataDir`
            // 가 그 상위 디렉터리(프로젝트 루트의 `.build/`) 내부에 있는지
            // 비교한다.
            let exePath = executableDir.path
            let normalizedExe = exePath.replacingOccurrences(of: "/", with: "\\").lowercased()
            guard let buildRange = normalizedExe.range(of: "\\.build\\") else {
                return false
            }
            let buildRoot = String(normalizedExe[..<buildRange.upperBound])
            // buildRoot 는 `c:\projects\kalsae\.build\` 같은 형태.
            let normalizedTarget = path.replacingOccurrences(of: "/", with: "\\").lowercased()
            return normalizedTarget.hasPrefix(buildRoot)
        }

        /// `%TEMP%/Kalsae/<identifier>/WebView2` 또는 `%LOCALAPPDATA%`,
        /// 둘 다 없으면 사용자 홈의 `.kalsae` 아래로 떨어진다. 절대 nil 이
        /// 되지 않는다.
        internal static func fallbackUserDataDir(identifier: String) -> String {
            let env = ProcessInfo.processInfo.environment
            let base: String
            if let temp = env["TEMP"], !temp.isEmpty {
                base = temp
            } else if let local = env["LOCALAPPDATA"], !local.isEmpty {
                base = local
            } else {
                base = NSHomeDirectory()
            }
            return (base as NSString)
                .appendingPathComponent("Kalsae")
                .appending("\\")
                .appending(identifier)
                .appending("\\WebView2")
        }

        private static func loadPolicy(executableDir: URL) -> Policy? {
            let url =
                executableDir
                .appendingPathComponent("kalsae.runtime.json")
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Policy.self, from: data)
        }

        /// Expands `%VAR%` Windows-style env tokens and resolves relative paths
        /// against `base`.
        static func expand(_ s: String, base: URL) -> String {
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
                    && !(s.count >= 2 && s[s.index(s.startIndex, offsetBy: 1)] == ":")
            {
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
