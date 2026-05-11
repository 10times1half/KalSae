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

            // Fast-path: WebView2 SDK 가 이미 모든 후보 루트에 설치돼 있으면
            // `swift package resolve` (Windows에서 ~1.5 s 소요) 를 건너뛴다.
            // 새 의존성이 추가돼 미해결된 체크아웃이 있으면 그건 후속
            // `swift build` 가 어차피 해결한다 — 여기서는 SDK 헤더 보장만 책임진다.
            //
            // 이 단축은 워크스페이스가 dirty 한 경우(예: `Package.swift` 수정 직후)
            // 에도 안전하다: 본 저장소 루트(cwd)에는 이미 헤더가 있고,
            // 새로 들어올 KalSae 체크아웃은 swift build 가 자체적으로 fetch 한 뒤
            // CKalsaeWV2 컴파일에서 헤더 부재로 실패해 사용자에게 명확히 알린다.
            //
            // 헤더만 있고 런타임 DLL 이 없는 부분 설치 상태에서도 fast-path 가
            // 통과하면 `stageLoaderDLL` 이 EXE 옆에 DLL 을 staging 하지 못해
            // 런타임에 `0x8007007E (ERROR_MOD_NOT_FOUND)` 로 환경 생성이
            // 조용히 실패한다. fast-path 는 헤더와 런타임 DLL 이 둘 다 존재할
            // 때만 통과시킨다.
            let preExistingRoots = discoverKalsaeRoots(cwd: cwd, fm: fm)
            let allProvisioned =
                !preExistingRoots.isEmpty
                && preExistingRoots.allSatisfy { root in
                    fm.fileExists(atPath: headerURL(in: root).path)
                        && fm.fileExists(atPath: runtimeDLLURL(in: root).path)
                }
            if allProvisioned {
                return
            }

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
                let header = headerURL(in: root)
                let runtime = runtimeDLLURL(in: root)
                let headerOK = fm.fileExists(atPath: header.path)
                let runtimeOK = fm.fileExists(atPath: runtime.path)
                if headerOK && runtimeOK { continue }

                guard autoFetch else {
                    let missing = headerOK ? runtime.path : header.path
                    throw ShellError.commandNotFound(
                        "WebView2 SDK at \(missing)"
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

                guard fm.fileExists(atPath: header.path),
                    fm.fileExists(atPath: runtime.path)
                else {
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

        // 로컬 경로 의존성 (`.package(path: ...)`) 은 `.build/checkouts/` 에
        // 들어오지 않고 사용자가 지정한 디스크 위치에 머무른다.
        // SwiftPM 이 resolve 후 작성하는 `.build/workspace-state.json` 에
        // 의존성 별 on-disk 경로가 들어 있으므로 그 경로들도 marker 검사 대상에
        // 추가한다. 파일이 없거나 스키마가 달라도 best-effort 로 무시한다.
        for candidate in workspaceStateLocalPaths(cwd: cwd, fm: fm) {
            if hasMarker(candidate), !roots.contains(candidate) {
                roots.append(candidate)
            }
        }
        return roots
    }

    /// `.build/workspace-state.json` 을 파싱해 로컬 경로 의존성의 on-disk
    /// 위치를 추출한다. 스키마는 SwiftPM 버전에 따라 변하므로 알려진
    /// 필드 이름들을 best-effort 로 모두 시도한다.
    private static func workspaceStateLocalPaths(cwd: URL, fm: FileManager) -> [URL] {
        let stateURL =
            cwd
            .appendingPathComponent(".build")
            .appendingPathComponent("workspace-state.json")
        guard let data = try? Data(contentsOf: stateURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }
        guard let object = json["object"] as? [String: Any],
            let deps = object["dependencies"] as? [[String: Any]]
        else {
            return []
        }
        var paths: [URL] = []
        for dep in deps {
            // 후보 키 — SwiftPM 6.x 까지 관찰된 이름들:
            //   state.path                              (fileSystem / edited)
            //   packageRef.location                     (fileSystem)
            //   packageRef.kind == "fileSystem"
            var candidate: String? = nil
            if let state = dep["state"] as? [String: Any],
                let p = state["path"] as? String
            {
                candidate = p
            }
            if candidate == nil,
                let ref = dep["packageRef"] as? [String: Any]
            {
                let kind = ref["kind"] as? String ?? ""
                if kind == "fileSystem" || kind == "localSourceControl",
                    let loc = ref["location"] as? String
                {
                    candidate = loc
                }
            }
            if let raw = candidate, !raw.isEmpty {
                paths.append(URL(fileURLWithPath: raw))
            }
        }
        return paths
    }

    /// SDK 헤더 (`WebView2.h`) 의 정규 경로. `CKalsaeWV2` 가
    /// `headerSearchPath` 로 가리키는 위치.
    private static func headerURL(in root: URL) -> URL {
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

    /// 런타임 로더 DLL 의 정규 경로. `stageLoaderDLL` 이 EXE 옆으로
    /// 복사하는 원본 위치이며, 누락 시 부팅 직후 환경 생성이
    /// `0x8007007E` 로 실패하므로 fast-path 의 필수 조건.
    private static func runtimeDLLURL(
        in root: URL,
        architecture: String = "win-x64"
    ) -> URL {
        root
            .appendingPathComponent("Sources")
            .appendingPathComponent("CKalsaeWV2")
            .appendingPathComponent("Vendor")
            .appendingPathComponent("WebView2")
            .appendingPathComponent("runtimes")
            .appendingPathComponent(architecture)
            .appendingPathComponent("native")
            .appendingPathComponent("WebView2Loader.dll")
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

    /// `WebView2Loader.dll` 을 `cwd/.build/<configuration>/` 에 복사한다.
    ///
    /// `CKalsaeWV2` 는 `LoadLibraryW("WebView2Loader.dll")` 로 런타임에 로더를
    /// 동적 로드하므로, 빌드 산출 EXE 옆에 DLL 이 없으면
    /// `HRESULT 0x8007007E (ERROR_MOD_NOT_FOUND)` 로 환경 생성에 실패한다.
    /// `swift run` / `swift build` 는 SDK 디렉터리에서 DLL 을 자동 복사하지 않으므로
    /// CLI 가 명시적으로 옮겨준다. 이미 동일 파일이 있으면 건너뛴다.
    ///
    /// - Parameters:
    ///   - cwd: 컨슈머 프로젝트 루트.
    ///   - configuration: `"debug"` 또는 `"release"`.
    ///   - architecture: NuGet 패키지 내 `runtimes/<arch>/native` 의 `<arch>`.
    ///     기본값은 `"win-x64"` — 현재 `Package.swift` 가 x64 만 링크 가능.
    ///
    /// - Throws: 어느 Kalsae 체크아웃에서도 `WebView2Loader.dll` 소스를 찾지
    ///   못하면 `ShellError.commandNotFound` 를 던진다. 이전에는 경고만 찍고
    ///   계속 진행했으나, 그 결과 EXE 옆에 DLL 이 없는 채로 부팅이 시작돼
    ///   런타임에 `CreateCoreWebView2EnvironmentWithOptions` 가
    ///   `0x8007007E (ERROR_MOD_NOT_FOUND)` 로 조용히 실패하고 윈도우가
    ///   즉시 닫혔다. 명확한 에러로 즉시 실패하도록 변경.
    public static func stageLoaderDLL(
        cwd: URL,
        configuration: String,
        architecture: String = "win-x64"
    ) throws {
        #if os(Windows)
            let fm = FileManager.default
            // SDK 가 설치된 첫 번째 루트에서 로더를 찾는다.
            let roots = discoverKalsaeRoots(cwd: cwd, fm: fm)
            let candidate = roots.lazy.compactMap { root -> URL? in
                let dll = runtimeDLLURL(in: root, architecture: architecture)
                return fm.fileExists(atPath: dll.path) ? dll : nil
            }.first

            guard let source = candidate else {
                throw ShellError.message(
                    "WebView2Loader.dll source not found under any Kalsae checkout."
                        + " Looked in .build/checkouts/*/Sources/CKalsaeWV2/Vendor/WebView2/runtimes/\(architecture)/native"
                        + " and in local path dependencies recorded in .build/workspace-state.json."
                        + " Re-run `kalsae dev` / `kalsae build` with auto-fetch enabled,"
                        + " or run Scripts/fetch-webview2.ps1 against the missing checkout.")
            }

            // 후보 출력 디렉터리:
            //   .build/<configuration>/                       (구버전 SwiftPM / 일부 호스트)
            //   .build/<triple>/<configuration>/              (Windows: x86_64-unknown-windows-msvc 등)
            // 둘 다 EXE 가 만들어질 수 있으므로 두 곳 모두 staging 한다.
            //
            // 알려진 Windows MSVC triple 만 직접 검사해 `.build/` 전체
            // 순회의 fileExists 호출을 절감한다 (RFC-002 §3.3). 향후
            // Swift 툴체인 이 새 triple naming 을 도입하면 행 추가 필요.
            var dests: [URL] = [
                cwd.appendingPathComponent(".build").appendingPathComponent(configuration)
            ]
            let buildDir = cwd.appendingPathComponent(".build")
            let knownTriples = [
                "x86_64-unknown-windows-msvc",
                "aarch64-unknown-windows-msvc",
            ]
            for triple in knownTriples {
                let triplePath =
                    buildDir
                    .appendingPathComponent(triple)
                    .appendingPathComponent(configuration)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: triplePath.path, isDirectory: &isDir),
                    isDir.boolValue
                {
                    dests.append(triplePath)
                }
            }

            for dest in dests {
                do {
                    try fm.createDirectory(
                        at: dest, withIntermediateDirectories: true)
                } catch {
                    print("⚠  Could not create \(dest.path): \(error)")
                    continue
                }
                let dst = dest.appendingPathComponent("WebView2Loader.dll")

                // 동일 크기면 스킵.
                if let srcAttrs = try? fm.attributesOfItem(atPath: source.path),
                    let dstAttrs = try? fm.attributesOfItem(atPath: dst.path),
                    let sSize = srcAttrs[.size] as? NSNumber,
                    let dSize = dstAttrs[.size] as? NSNumber,
                    sSize == dSize
                {
                    continue
                }

                if fm.fileExists(atPath: dst.path) {
                    try? fm.removeItem(at: dst)
                }
                do {
                    try fm.copyItem(at: source, to: dst)
                    print("📎  Staged WebView2Loader.dll → \(dst.path)")
                } catch {
                    print("⚠  Failed to stage WebView2Loader.dll to \(dst.path): \(error)")
                }
            }
        #endif
    }
}
