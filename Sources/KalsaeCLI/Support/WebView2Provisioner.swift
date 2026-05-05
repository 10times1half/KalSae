/// `kalsae dev` 와 `kalsae build` 가 공유하는 WebView2 SDK 프로비저너.
///
/// 컨슈머 프로젝트에서 `swift run` / `swift build` 가 `CKalsaeWV2` 를 컴파일할 때
/// `Sources/CKalsaeWV2/Vendor/WebView2/build/native/include/WebView2.h` 가 필요하다.
/// 이 파일들은 라이선스상 git에 체크인하지 않으므로 (`.gitignore`),
/// SwiftPM 체크아웃 디렉터리에 NuGet 에서 받아 채워야 한다.
/// 빌드 시 WebView2Loader.dll 을 동적 로드하므로 정적 라이브러리는 불필요하다.
///
/// 수행 위치:
/// - `cwd` 자체 (Kalsae 본 저장소를 직접 빌드하는 경우)
/// - `cwd/.build/checkouts/*` 중 `Sources/CKalsaeWV2/include/` 가 있는 디렉터리
///   (Kalsae 를 SwiftPM URL 의존성으로 사용하는 경우)
///
/// 경로 의존성(`.package(path:)`)은 사용자가 직접 관리하는 체크아웃이므로
/// 자동 프로비저닝하지 않는다 — 누락 시 명확한 오류 메시지로 안내한다.
public import Foundation

public enum KSWebView2Provisioner {
    /// 빌드 진행 전 WebView2 SDK 가 필요한 모든 디렉터리에 SDK 를 보장한다.
    /// Windows 가 아니면 no-op.
    ///
    /// - Parameters:
    ///   - cwd: 컨슈머 프로젝트 루트.
    ///   - autoFetch: SDK 가 없을 때 `Scripts/fetch-webview2.ps1` 를 자동 실행할지 여부.
    ///   - sdkVersion: NuGet 에서 받을 WebView2 SDK 버전 (`"latest"` 또는 명시 버전).
    ///   - resolveBeforeProvision: `swift package resolve` 를 먼저 실행해
    ///     `.build/checkouts/` 가 채워지도록 강제한다. `kalsae dev` / `kalsae build`
    ///     의 `swift run` / `swift build` 호출 직전에 호출되므로 기본값은 `true`.
    public static func ensure(
        cwd: URL,
        autoFetch: Bool,
        sdkVersion: String,
        resolveBeforeProvision: Bool = true
    ) throws {
        #if os(Windows)
            let fm = FileManager.default

            if resolveBeforeProvision {
                // `.build/checkouts/` 를 채우기 위해 먼저 dependency resolve 를 강제.
                // 이 단계가 SDK 다운로드를 트리거하지는 않으나, 체크아웃이 없으면
                // 우리가 프로비저닝해야 할 위치도 알 수 없다.
                _ = try? shell(command: "swift", arguments: ["package", "resolve"], in: cwd.path)
            }

            let roots = discoverKalsaeRoots(cwd: cwd, fm: fm)
            // fetch-webview2.ps1 는 Kalsae 체크아웃 (Sources/CKalsaeWV2/include 마커 보유) 안에만
            // 존재한다. 컨슈머 cwd 에도 SDK 를 설치할 때 그 스크립트를 재사용한다.
            let scriptRoot = roots.first { root in
                fm.fileExists(
                    atPath:
                        root
                        .appendingPathComponent("Scripts")
                        .appendingPathComponent("fetch-webview2.ps1").path)
            }

            for root in roots {
                let loader = loaderURL(in: root)
                if fm.fileExists(atPath: loader.path) { continue }

                guard autoFetch else {
                    throw ShellError.commandNotFound(
                        "WebView2 SDK at \(loader.path)"
                            + " — re-run with auto-fetch enabled, or run"
                            + " Scripts/fetch-webview2.ps1 -ProjectRoot \(root.path).")
                }

                guard let scriptRoot else {
                    throw ShellError.commandNotFound(
                        "Scripts/fetch-webview2.ps1 (no Kalsae checkout located).")
                }

                try fetchWebView2(
                    scriptRoot: scriptRoot,
                    installRoot: root,
                    sdkVersion: sdkVersion,
                    fm: fm)

                guard fm.fileExists(atPath: loader.path) else {
                    throw ShellError.nonZeroExit(1)
                }
            }
        #endif
    }

    // MARK: - 내부

    /// `Sources/CKalsaeWV2/include/` 가 존재하는 모든 디렉터리.
    ///
    /// `Package.swift` 에서 `.unsafeFlags(["-L", ...])` 와 `WebView2LoaderStatic` 링크를
    /// 제거했으므로 헤더(`headerSearchPath` 기준 디렉터리)만 채우면 된다.
    /// 컨슈머 cwd 는 더 이상 install root 에 추가하지 않는다.
    private static func discoverKalsaeRoots(cwd: URL, fm: FileManager) -> [URL] {
        var roots: [URL] = []
        let marker = ["Sources", "CKalsaeWV2", "include"]

        func hasMarker(_ url: URL) -> Bool {
            var probe = url
            for component in marker { probe.appendPathComponent(component) }
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: probe.path, isDirectory: &isDir) && isDir.boolValue
        }

        if hasMarker(cwd) { roots.append(cwd) }

        let checkouts =
            cwd
            .appendingPathComponent(".build")
            .appendingPathComponent("checkouts")
        if let children = try? fm.contentsOfDirectory(
            at: checkouts,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        {
            for child in children where hasMarker(child) {
                roots.append(child)
            }
        }
        return roots
    }

    private static func loaderURL(in root: URL) -> URL {
        root
            .appendingPathComponent("Sources")
            .appendingPathComponent("CKalsaeWV2")
            .appendingPathComponent("Vendor")
            .appendingPathComponent("WebView2")
            .appendingPathComponent("build")
            .appendingPathComponent("native")
            .appendingPathComponent("include")
            .appendingPathComponent("WebView2.h")
    }

    /// `scriptRoot/Scripts/fetch-webview2.ps1` 를 실행해 `installRoot/Vendor/WebView2/` 를 채운다.
    /// 두 인자가 다른 디렉터리일 수 있다 (컨슈머 cwd 에 설치할 때 스크립트는 Kalsae 체크아웃에서 가져옴).
    private static func fetchWebView2(
        scriptRoot: URL,
        installRoot: URL,
        sdkVersion: String,
        fm: FileManager
    ) throws {
        let candidate =
            scriptRoot
            .appendingPathComponent("Scripts")
            .appendingPathComponent("fetch-webview2.ps1")
        guard fm.fileExists(atPath: candidate.path) else {
            throw ShellError.commandNotFound(
                "Scripts/fetch-webview2.ps1 (looked in \(candidate.path))")
        }

        let shellName: String
        if findExecutable(named: "pwsh") != nil {
            shellName = "pwsh"
        } else if findExecutable(named: "powershell") != nil {
            shellName = "powershell"
        } else {
            throw ShellError.shellUnavailable
        }

        var args = [
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", candidate.path,
            "-ProjectRoot", installRoot.path,
        ]
        let trimmed = sdkVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.lowercased() != "latest" {
            args += ["-Version", trimmed]
        }

        print("⬇️  WebView2 SDK not found in \(installRoot.path) — fetching...")
        try shell(command: shellName, arguments: args, in: installRoot.path)
    }
}
