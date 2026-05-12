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
            // 이전에는 fetch-webview2.ps1 를 PowerShell 로 실행했으나, NuGet
            // 패키지 다운로드/추출 로직을 Swift 로 포팅해 PowerShell 의존성을 제거.
            // scriptRoot 탐색이 더 이상 필요 없다.

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

                try fetchWebView2(
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
        // Windows 파일시스템은 case-insensitive 이고, URL 식별성 비교는 trailing
        // slash / 대소문자 차이로 같은 디렉터리를 다른 항목으로 본다. 정규화된
        // 경로 문자열 기준으로 dedup 한다.
        var seen: Set<String> = []
        let marker = ["Sources", "CKalsaeWV2", "include"]

        func hasMarker(_ url: URL) -> Bool {
            var probe = url
            for component in marker { probe.appendPathComponent(component) }
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: probe.path, isDirectory: &isDir) && isDir.boolValue
        }

        func append(_ url: URL) {
            let key = url.standardizedFileURL.path.lowercased()
            if seen.insert(key).inserted {
                roots.append(url)
            }
        }

        if hasMarker(cwd) { append(cwd) }

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
                append(child)
            }
        }

        // 로컬 경로 의존성 (`.package(path: ...)`) 은 `.build/checkouts/` 에
        // 들어오지 않고 사용자가 지정한 디스크 위치에 머무른다.
        // SwiftPM 이 resolve 후 작성하는 `.build/workspace-state.json` 에
        // 의존성 별 on-disk 경로가 들어 있으므로 그 경로들도 marker 검사 대상에
        // 추가한다. 파일이 없거나 스키마가 달라도 best-effort 로 무시한다.
        for candidate in workspaceStateLocalPaths(cwd: cwd, fm: fm) where hasMarker(candidate) {
            append(candidate)
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
        // SwiftPM <= 6.0 은 `object.dependencies` 로 래핑하지만, 6.1+ (workspace
        // state schema v7+) 는 top-level `dependencies` 로 평탄화한다. 두 스키마
        // 모두 best-effort 로 시도한다.
        let deps: [[String: Any]] =
            (json["object"] as? [String: Any])?["dependencies"] as? [[String: Any]]
            ?? json["dependencies"] as? [[String: Any]]
            ?? []
        if deps.isEmpty {
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

    /// `installRoot/Sources/CKalsaeWV2/Vendor/WebView2/` 에 NuGet 패키지
    /// `Microsoft.Web.WebView2` 의 헤더 + 런타임 DLL 을 설치한다.
    /// 이전에는 `Scripts/fetch-webview2.ps1` 을 PowerShell 로 실행했으나,
    /// PowerShell 의존성을 제거하기 위해 Swift 로 인라인 포팅됨.
    /// (`fetch-webview2.ps1` 은 사용자 수동 실행 경로로 그대로 남아 있다.)
    private static func fetchWebView2(
        installRoot: URL,
        sdkVersion: String,
        fm: FileManager
    ) throws {
        // 1) 버전 결정 — "latest" 면 NuGet flat-container index 에서 마지막 stable 추출.
        var resolvedVersion = sdkVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedVersion.isEmpty || resolvedVersion.lowercased() == "latest" {
            resolvedVersion = try fetchLatestWebView2Version()
        }

        print("⬇️  WebView2 SDK \(resolvedVersion) — fetching into \(installRoot.path)...")

        let dest =
            installRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("CKalsaeWV2")
            .appendingPathComponent("Vendor")
            .appendingPathComponent("WebView2")

        // 2) .nupkg 다운로드 (zip).
        let nupkgURLString =
            "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/"
            + "\(resolvedVersion)/microsoft.web.webview2.\(resolvedVersion).nupkg"
        guard let nupkgURL = URL(string: nupkgURLString) else {
            throw ShellError.message("Failed to construct NuGet URL: \(nupkgURLString)")
        }
        let tmpRoot = fm.temporaryDirectory
            .appendingPathComponent("wv2-\(resolvedVersion)-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpRoot) }

        let nupkgPath = tmpRoot.appendingPathExtension("zip")
        let data: Data
        do {
            data = try Data(contentsOf: nupkgURL)
        } catch {
            throw ShellError.message(
                "Failed to download \(nupkgURLString): \(error.localizedDescription)")
        }
        try data.write(to: nupkgPath, options: [.atomic])

        // 3) 추출.
        let extractDir = tmpRoot.appendingPathComponent("extracted")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        do {
            try KSZipArchiver.unzip(archive: nupkgPath, to: extractDir)
        } catch {
            throw ShellError.message(
                "Failed to extract WebView2 nupkg: \(error)")
        }

        // 4) 기존 dest 제거 후 재생성.
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        // 5) 헤더 복사.
        let includeSrc = extractDir
            .appendingPathComponent("build")
            .appendingPathComponent("native")
            .appendingPathComponent("include")
        let includeDst = dest
            .appendingPathComponent("build")
            .appendingPathComponent("native")
            .appendingPathComponent("include")
        try fm.createDirectory(at: includeDst, withIntermediateDirectories: true)
        if let entries = try? fm.contentsOfDirectory(at: includeSrc, includingPropertiesForKeys: nil) {
            for src in entries {
                let dst = includeDst.appendingPathComponent(src.lastPathComponent)
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.copyItem(at: src, to: dst)
            }
        }

        // 6) 런타임 DLL 복사 (arch 별).
        for arch in ["win-x64", "win-x86", "win-arm64"] {
            let srcDLL = extractDir
                .appendingPathComponent("runtimes")
                .appendingPathComponent(arch)
                .appendingPathComponent("native")
                .appendingPathComponent("WebView2Loader.dll")
            guard fm.fileExists(atPath: srcDLL.path) else { continue }
            let dstDir = dest
                .appendingPathComponent("runtimes")
                .appendingPathComponent(arch)
                .appendingPathComponent("native")
            try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
            let dstDLL = dstDir.appendingPathComponent("WebView2Loader.dll")
            if fm.fileExists(atPath: dstDLL.path) { try fm.removeItem(at: dstDLL) }
            try fm.copyItem(at: srcDLL, to: dstDLL)
        }

        // 7) 라이선스.
        for name in ["LICENSE.txt", "THIRD_PARTY_NOTICES.txt"] {
            let src = extractDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = dest.appendingPathComponent(name)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.copyItem(at: src, to: dst)
        }

        // 8) 버전 마커.
        try Data(resolvedVersion.utf8).write(
            to: dest.appendingPathComponent("VERSION.txt"), options: [.atomic])
    }

    /// NuGet flat-container index 에서 마지막 stable (prerelease 제외) 버전 추출.
    private static func fetchLatestWebView2Version() throws -> String {
        let indexURLString =
            "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json"
        guard let indexURL = URL(string: indexURLString) else {
            throw ShellError.message("Failed to construct NuGet index URL.")
        }
        let data: Data
        do {
            data = try Data(contentsOf: indexURL)
        } catch {
            throw ShellError.message(
                "Failed to query NuGet for latest WebView2 version: \(error.localizedDescription)")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let versions = json["versions"] as? [String]
        else {
            throw ShellError.message("Unexpected NuGet index schema.")
        }
        guard let last = versions.last(where: { !$0.contains("-") }) else {
            throw ShellError.message("No stable WebView2 version found on NuGet.")
        }
        return last
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
            //   .build/<triple>/<configuration>/              (Windows: x86_64-unknown-windows-msvc 등)
            //   .build/<configuration>/                       (SwiftPM 가 빌드 후 만드는 symlink)
            //
            // 신선한 체크아웃에서는 두 경로 모두 존재하지 않는다.
            // `.build/<configuration>/` 를 미리 *실제 디렉터리*로 생성하면 SwiftPM 이
            // 빌드 후 symlink 를 만들 자리를 차지해버려, EXE 는 `.build/<triple>/<configuration>/`
            // 에 만들어지고 DLL 은 분리된 실 디렉터리에 남아 `LoadLibraryW("WebView2Loader.dll")`
            // 가 0x8007007E 로 실패한다. 따라서 triple 디렉터리만 보장 생성하고,
            // `.build/<configuration>/` 는 이미 존재할 때(symlink 또는 dir) 만 추가 staging.
            //
            // 현재 호스트 triple 을 컴파일타임 arch 매크로로 결정한다 — CLI 자체가
            // 컨슈머 프로젝트와 같은 아키텍처로 빌드되기 때문에 일반적으로 일치한다.
            #if arch(arm64)
                let hostTriple = "aarch64-unknown-windows-msvc"
            #else
                let hostTriple = "x86_64-unknown-windows-msvc"
            #endif

            let buildDir = cwd.appendingPathComponent(".build")
            var dests: [URL] = [
                buildDir
                    .appendingPathComponent(hostTriple)
                    .appendingPathComponent(configuration)
            ]

            // 다른 알려진 triple 디렉터리가 이미 존재하면 그곳에도 staging 한다
            // (예: 동일 체크아웃을 x64/arm64 둘 다로 빌드한 경우).
            let knownTriples = [
                "x86_64-unknown-windows-msvc",
                "aarch64-unknown-windows-msvc",
            ]
            for triple in knownTriples where triple != hostTriple {
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

            // `.build/<configuration>/` 가 이미 symlink/실 dir 로 존재하면 함께 stage.
            // (존재하지 않으면 새로 만들지 않는다 — SwiftPM 의 symlink 생성을 방해하지 않기 위함.)
            let legacyDest = buildDir.appendingPathComponent(configuration)
            if fm.fileExists(atPath: legacyDest.path) {
                dests.append(legacyDest)
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

                // 크기 + mtime 으로 동일성 판단. 크기만 비교하면 NuGet 패키지
                // 업데이트 후 우연히 같은 크기인 새 DLL 을 stale 사본으로 잘못
                // 보존할 수 있어 디버깅이 어려워진다. dest mtime 이 source mtime
                // 이상이고 크기까지 같을 때만 skip.
                if let srcAttrs = try? fm.attributesOfItem(atPath: source.path),
                    let dstAttrs = try? fm.attributesOfItem(atPath: dst.path),
                    let sSize = srcAttrs[.size] as? NSNumber,
                    let dSize = dstAttrs[.size] as? NSNumber,
                    sSize == dSize,
                    let sMtime = srcAttrs[.modificationDate] as? Date,
                    let dMtime = dstAttrs[.modificationDate] as? Date,
                    dMtime >= sMtime
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
