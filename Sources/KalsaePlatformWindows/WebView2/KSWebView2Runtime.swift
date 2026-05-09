#if os(Windows)
    import Foundation
    internal import KalsaeCore
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
            var embeddedAssetsEnabled: Bool?
            var embeddedAssetsResourceName: String?
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

        internal static func embeddedAssetsResourceName(executableDir: URL) -> String? {
            guard
                let policy = loadPolicy(executableDir: executableDir),
                policy.embeddedAssetsEnabled == true,
                let resourceName = policy.embeddedAssetsResourceName,
                !resourceName.isEmpty
            else {
                return nil
            }
            return resourceName
        }

        internal static func embeddedAssetsExtractionDirectory(
            identifier: String,
            resourceName: String,
            processID: Int32 = Int32(ProcessInfo.processInfo.processIdentifier),
            env: [String: String] = ProcessInfo.processInfo.environment
        ) -> URL {
            let base: String
            if let temp = env["TEMP"], !temp.isEmpty {
                base = temp
            } else if let local = env["LOCALAPPDATA"], !local.isEmpty {
                base = local
            } else {
                base = NSTemporaryDirectory()
            }

            return URL(fileURLWithPath: base)
                .appendingPathComponent("Kalsae")
                .appendingPathComponent(identifier)
                .appendingPathComponent("EmbeddedAssets")
                .appendingPathComponent(resourceName)
                .appendingPathComponent(String(processID))
        }

        internal static func resolveEmbeddedAssetsDirectory(
            executableDir: URL,
            identifier: String
        ) -> URL? {
            guard
                let resourceName = embeddedAssetsResourceName(executableDir: executableDir),
                let zipData = loadEmbeddedResource(named: resourceName)
            else {
                return nil
            }

            do {
                return try materializeEmbeddedAssets(
                    zipData: zipData,
                    identifier: identifier,
                    resourceName: resourceName)
            } catch {
                // RFC-010 Phase 3: Log extraction error for diagnostics
                KSLog.logger("kalsae.asset-extract").error(
                    "Failed to extract embedded assets: \(error)")
                return nil
            }
        }

        internal static func hasEmbeddedAssetsResource(executableDir: URL) -> Bool {
            guard let resourceName = embeddedAssetsResourceName(executableDir: executableDir) else {
                return false
            }
            return loadEmbeddedResource(named: resourceName) != nil
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

        /// Removes stale temp folders from previous app executions.
        /// Scans `%TEMP%/Kalsae/<identifier>/EmbeddedAssets/` for PID-named
        /// subfolders and deletes those that don't correspond to any running process.
        internal static func cleanupStaleTempFolders(identifier: String) {
            let env = ProcessInfo.processInfo.environment
            let base: String
            if let temp = env["TEMP"], !temp.isEmpty {
                base = temp
            } else if let local = env["LOCALAPPDATA"], !local.isEmpty {
                base = local
            } else {
                base = NSTemporaryDirectory()
            }

            let basePath = (base as NSString)
                .appendingPathComponent("Kalsae")
                .appendingPathComponent(identifier)
                .appendingPathComponent("EmbeddedAssets")

            let fm = FileManager.default
            guard fm.fileExists(atPath: basePath) else { return }

            do {
                let resourceFolders = try fm.contentsOfDirectory(atPath: basePath)
                for resourceName in resourceFolders {
                    let resourcePath = (basePath as NSString).appendingPathComponent(resourceName)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: resourcePath, isDirectory: &isDir),
                        isDir.boolValue else { continue }

                    let pidFolders = try fm.contentsOfDirectory(atPath: resourcePath)
                    for pidFolder in pidFolders {
                        guard let pid = Int(pidFolder) else { continue }
                        let pidPath = (resourcePath as NSString).appendingPathComponent(pidFolder)

                        // Only delete if this PID is not currently running
                        if !isProcessRunning(Int32(pid)) {
                            try? fm.removeItem(atPath: pidPath)
                        }
                    }
                }
            } catch {
                // Best-effort cleanup; silently continue on error
            }
        }

        /// Checks if a process with the given PID is currently running.
        private static func isProcessRunning(_ pid: Int32) -> Bool {
            let handle = OpenProcess(
                DWORD(PROCESS_QUERY_LIMITED_INFORMATION),
                false,
                DWORD(pid))
            guard handle != nil else { return false }

            defer { _ = CloseHandle(handle) }

            var creationTime = FILETIME()
            var exitTime = FILETIME()
            var kernelTime = FILETIME()
            var userTime = FILETIME()

            let result = GetProcessTimes(
                handle,
                &creationTime,
                &exitTime,
                &kernelTime,
                &userTime)

            return result
        }

        private static func materializeEmbeddedAssets(
            zipData: Data,
            identifier: String,
            resourceName: String
        ) throws(KSError) -> URL {
            let fm = FileManager.default
            let workDir = embeddedAssetsExtractionDirectory(
                identifier: identifier,
                resourceName: resourceName)
            let outputDir = workDir.appendingPathComponent("root")
            let zipURL = workDir.appendingPathComponent("assets.zip")

            if fm.fileExists(atPath: workDir.path) {
                try? fm.removeItem(at: workDir)
            }

            do {
                try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
                try zipData.write(to: zipURL, options: [.atomic])
                defer { try? fm.removeItem(at: zipURL) }
                try extractEmbeddedAssets(zipURL: zipURL, outputDir: outputDir)
                return outputDir
            } catch let error as KSError {
                throw error
            } catch {
                throw KSError(
                    code: .ioFailed,
                    message: "Failed to materialize embedded frontend assets: \(error)")
            }
        }

        private static func extractEmbeddedAssets(
            zipURL: URL,
            outputDir: URL
        ) throws(KSError) {
            let toolPath = "C:\\Windows\\System32\\tar.exe"
            guard FileManager.default.fileExists(atPath: toolPath) else {
                throw KSError(
                    code: .ioFailed,
                    message: "Embedded asset extraction requires tar.exe at \(toolPath)")
            }

            let stderr = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: toolPath)
            process.arguments = ["-x", "-f", zipURL.path, "-C", outputDir.path]
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                throw KSError(
                    code: .ioFailed,
                    message: "Failed to launch tar.exe for embedded asset extraction: \(error)")
            }

            guard process.terminationStatus == 0 else {
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? "unknown error"
                throw KSError(
                    code: .ioFailed,
                    message: "Embedded asset extraction failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        private static func loadEmbeddedResource(named resourceName: String) -> Data? {
            let resourceType = UnsafePointer<WCHAR>(bitPattern: 10)
            guard let resourceType else { return nil }

            return resourceName.withCString(encodedAs: UTF16.self) { resourceNamePtr in
                guard let resource = FindResourceW(nil, resourceNamePtr, resourceType) else {
                    return nil
                }
                let size = SizeofResource(nil, resource)
                guard size > 0,
                    let handle = LoadResource(nil, resource),
                    let bytes = LockResource(handle)
                else {
                    return nil
                }

                return Data(bytes: bytes, count: Int(size))
            }
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
