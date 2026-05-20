/// Windows Swift 런타임 + VC 재배포 DLL 자동 staging.
///
/// Swift on Windows 는 `swift_Concurrency.dll`, `swiftCore.dll`,
/// `Foundation.dll` 등을 **동적으로** 링크한다. 정적 링크가 불가능하므로
/// 빌드 산출물을 다른 PC 에 배포하려면 이 DLL 들을 EXE 옆에 동봉해야 한다.
///
/// 이 모듈은 [Scripts/stage-windows-cli-runtime.ps1] 의 동작을 순수 Swift 로
/// 포팅한 것이다:
///
/// 1. `KSPEImportReader` 로 EXE 의 import 테이블에서 의존 DLL 이름 추출
/// 2. 화이트리스트(`swift*`, `Foundation*`, `dispatch.dll`, `vcruntime140*` …)
///    매칭된 DLL 만 EXE 옆으로 복사
/// 3. 새로 복사된 DLL 의 의존성도 BFS 로 재귀 처리 (icu, swift_StringProcessing 등)
///
/// PowerShell / dumpbin / VS Build Tools 런타임 의존성 없음.
///
/// Windows 가 아닌 호스트에서는 모든 진입점이 **no-op** 으로 동작해 0 을 반환한다.
public import Foundation

public enum KSWindowsRuntimeStager {
    /// `executable` 옆에 (또는 `destination` 이 주어지면 그 디렉터리에) Swift
    /// 런타임 + VC 재배포 DLL 을 staging 한다.
    ///
    /// - Parameters:
    ///   - executable: 분석할 EXE 의 URL.
    ///   - destination: DLL 을 복사할 디렉터리. `nil` 이면 `executable` 의
    ///     부모 디렉터리에 staging.
    ///   - extraSearchDirs: PATH/Runtimes 외에 추가로 뒤질 디렉터리.
    /// - Returns: 실제로 복사된 DLL 개수. 이미 최신이면 0.
    /// - Throws: `ShellError.message` — EXE 파싱 실패 시.
    @discardableResult
    public static func stage(
        executable: URL,
        destination: URL? = nil,
        extraSearchDirs: [URL] = []
    ) throws -> Int {
        #if os(Windows)
            let fm = FileManager.default
            let dest = destination ?? executable.deletingLastPathComponent()
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)

            let searchDirs = discoverSearchDirs(fm: fm) + extraSearchDirs

            // BFS: 큐에는 import 의존성을 분석할 파일 경로가 들어간다.
            // visited 는 lower-cased DLL 이름 집합. 이미 staging 했거나
            // 화이트리스트 밖이면 다시 처리하지 않는다.
            var queue: [URL] = [executable]
            var visited = Set<String>()
            var unresolved: [String] = []
            var staged = 0

            while !queue.isEmpty {
                let current = queue.removeFirst()
                let deps: [String]
                do {
                    deps = try KSPEImportReader.importedDLLs(at: current)
                } catch {
                    // 부분 실패는 경고로만 — 첫 EXE 가 실패하면 어차피 staged==0.
                    print("⚠  PE parse failed for \(current.lastPathComponent): \(error)")
                    continue
                }

                for dep in deps {
                    let key = dep.lowercased()
                    if !visited.insert(key).inserted { continue }
                    if !isWhitelisted(key) { continue }

                    // 화이트리스트 통과 → 검색 디렉터리에서 실제 파일을 찾는다.
                    guard let source = findDLL(named: dep, in: searchDirs, fm: fm) else {
                        // 못 찾아도 hard-fail 하지 않는다: 시스템 DLL 일 수 있고,
                        // CRT 가 OS 에 사전 설치돼 있을 수도 있다.
                        // 단, Swift/Foundation 처럼 진짜 필요한 DLL 이 빠진 채
                        // dist 가 만들어지면 다른 PC 에서 `swiftCore.dll not found`
                        // 다이얼로그로 끝나므로 어떤 이름이 못 잡혔는지 로그에는 남긴다.
                        unresolved.append(dep)
                        continue
                    }
                    let dst = dest.appendingPathComponent(dep)
                    if isUpToDate(source: source, destination: dst, fm: fm) {
                        // BFS 는 계속해야 한다 — 재귀 의존성이 아직 누락됐을 수 있다.
                        queue.append(dst)
                        continue
                    }
                    if fm.fileExists(atPath: dst.path) {
                        try? fm.removeItem(at: dst)
                    }
                    do {
                        try fm.copyItem(at: source, to: dst)
                        staged += 1
                        queue.append(dst)
                    } catch {
                        print("⚠  Failed to stage \(dep) → \(dst.path): \(error)")
                    }
                }
            }

            if staged > 0 {
                print("📎  Staged \(staged) Windows runtime DLL\(staged == 1 ? "" : "s") → \(dest.path)")
            }
            if !unresolved.isEmpty {
                let names = unresolved.sorted().joined(separator: ", ")
                print(
                    "⚠  Swift runtime DLL\(unresolved.count == 1 ? "" : "s") not located on host "
                        + "(packaged app may fail with `<name>.dll not found` on other PCs): \(names). "
                        + "Ensure the Swift toolchain's `Runtimes/<ver>/usr/bin` is on PATH.")
            }
            return staged
        #else
            _ = executable
            _ = destination
            _ = extraSearchDirs
            return 0
        #endif
    }

    // MARK: - Whitelist

    /// DLL 이름이 Swift 런타임 / VC 재배포 화이트리스트에 해당하는지.
    /// 인자는 소문자라고 가정한다.
    static func isWhitelisted(_ lowerName: String) -> Bool {
        for prefix in whitelistPrefixes {
            if lowerName.hasPrefix(prefix) { return true }
        }
        return whitelistExact.contains(lowerName)
    }

    /// `executable` 의 PE import 테이블에 화이트리스트 DLL 이 하나라도
    /// 포함돼 있는지. Packager 가 `stage` 결과가 0 일 때 진짜로 staging 이
    /// 필요했는지(= 경고를 띄울지) 판정하는 데 사용.
    ///
    /// 파싱 실패 시 false (조용히 통과 — staging 실패는 이미 별도 경고).
    public static func hasWhitelistedImports(executable: URL) -> Bool {
        guard let deps = try? KSPEImportReader.importedDLLs(at: executable) else {
            return false
        }
        return deps.contains { isWhitelisted($0.lowercased()) }
    }

    /// `hasPrefix` 검사용 (모두 소문자). 끝은 `.dll` 로 끝난다는 전제.
    private static let whitelistPrefixes: [String] = [
        "swift",  // swiftCore.dll, swift_Concurrency.dll, swiftFoundation.dll, ...
        "_concurrency",  // _Concurrency.dll (some toolchain variants)
        "_stringprocessing",
        "_foundation",
        "foundation",
        "icudt",
        "icuuc",
        "icuin",
        "icuio",
        "vcruntime140",
        "msvcp140",
    ]

    private static let whitelistExact: Set<String> = [
        "dispatch.dll",
        "blocksruntime.dll",
        "_internationalizationstubs.dll",
        "concrt140.dll",
    ]

    // MARK: - Search dir discovery (Windows only)

    #if os(Windows)
        /// Swift 런타임 / VC 재배포 DLL 을 검색할 디렉터리 후보.
        ///
        /// 순서 (Runtimes 우선):
        ///   1. `swift.exe` 인근 `Runtimes/<ver>/usr/bin` (`swift.exe` 부모에서
        ///      위로 6 단계 검색) — **비-Asserts** 변종이 여기에 있다.
        ///   2. `swift.exe` 가 위치한 디렉터리 (PATH 에서 검색) — fallback.
        ///      주의: 공식 swift.org Windows installer 는 `Toolchains\<ver>+Asserts`
        ///      에 +Asserts 변종 dispatch.dll 을 둘 수 있다. 이 DLL 은 libdispatch
        ///      내부 assert 가 활성화돼 사소한 contract 위반에도 __builtin_trap →
        ///      STATUS_ILLEGAL_INSTRUCTION (0xc000001d) 으로 강제 종료된다.
        ///      배포 바이너리에는 Runtimes 쪽 비-Asserts 변종을 동봉해야 한다.
        ///   3. `%PATH%` 에 등록된 모든 디렉터리 (swift.org 공식 인스톨러는
        ///      `Runtimes\<ver>\usr\bin` 을 PATH 에 직접 추가하므로 휴리스틱 워크업이
        ///      빗나가도 여기서 잡힌다)
        ///   4. `%SystemRoot%\System32` (vcruntime fallback)
        ///   5. VS Build Tools 의 VC redist 디렉터리 (`Microsoft.VC*.CRT`)
        static func discoverSearchDirs(
            fm: FileManager,
            env: [String: String] = ProcessInfo.processInfo.environment
        ) -> [URL] {
            var dirs: [URL] = []
            var seen = Set<String>()

            func add(_ url: URL) {
                let key = url.path.lowercased()
                if seen.insert(key).inserted, fm.fileExists(atPath: url.path) {
                    dirs.append(url)
                }
            }

            // 1) swift.exe 인근 Runtimes/<ver>/usr/bin (먼저 추가).
            // 공식 swift.org Windows installer 는
            // `<install>\Toolchains\<ver>\usr\bin\swift.exe` 와
            // `<install>\Runtimes\<ver>\usr\bin\swiftCore.dll` 레이아웃이므로
            // swiftDir 에서 4 단계 위 (`<install>`) 에 도달해야 `Runtimes` 형제가
            // 보인다. 6 으로 잡아 chocolatey/scoop/MS Store 변형도 흡수.
            let swiftDir = locateSwiftDir(fm: fm, env: env)
            if let swiftDir {
                var anchor = swiftDir
                for _ in 0..<6 {
                    anchor = anchor.deletingLastPathComponent()
                    let runtimes = anchor.appendingPathComponent("Runtimes")
                    if let entries = try? fm.contentsOfDirectory(
                        at: runtimes,
                        includingPropertiesForKeys: nil)
                    {
                        for entry in entries {
                            let bin = entry.appendingPathComponent("usr/bin")
                            add(bin)
                        }
                    }
                }
                // 2) swift.exe 디렉터리 (fallback — +Asserts 변종일 수 있음).
                add(swiftDir)
            }

            // 3) %PATH% 전체 — Swift Windows installer 가 Runtimes\<ver>\usr\bin 을
            // PATH 에 등록하므로, 워크업이 실패해도 여기서 잡힌다.
            // 비 화이트리스트 DLL 은 어차피 `isWhitelisted()` 에서 거르므로 안전.
            if let pathEnv = env["PATH"] {
                for entry in pathEnv.split(separator: ";") {
                    let trimmed = entry.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty { continue }
                    add(URL(fileURLWithPath: trimmed))
                }
            }

            // 4) System32 (vcruntime140.dll 등)
            let systemRoot = env["SystemRoot"] ?? "C:\\Windows"
            add(URL(fileURLWithPath: systemRoot).appendingPathComponent("System32"))

            // 5) VS Build Tools redist
            let pf = env["ProgramFiles"] ?? "C:\\Program Files"
            let pfx = env["ProgramFiles(x86)"] ?? "C:\\Program Files (x86)"
            for base in [pf, pfx] {
                let vs = URL(fileURLWithPath: base)
                    .appendingPathComponent("Microsoft Visual Studio")
                    .appendingPathComponent("2022")
                if let editions = try? fm.contentsOfDirectory(
                    at: vs, includingPropertiesForKeys: nil)
                {
                    for edition in editions {
                        let redistRoot = edition.appendingPathComponent("VC/Redist/MSVC")
                        if let versions = try? fm.contentsOfDirectory(
                            at: redistRoot, includingPropertiesForKeys: nil)
                        {
                            for ver in versions {
                                let arch = ver.appendingPathComponent("x64")
                                if let crtDirs = try? fm.contentsOfDirectory(
                                    at: arch, includingPropertiesForKeys: nil)
                                {
                                    for crt in crtDirs
                                    where crt.lastPathComponent.hasPrefix("Microsoft.VC")
                                        && crt.lastPathComponent.hasSuffix(".CRT")
                                    {
                                        add(crt)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            return dirs
        }

        private static func locateSwiftDir(fm: FileManager, env: [String: String]) -> URL? {
            // 1) PATH 직접 스캔.
            if let path = env["PATH"] {
                for entry in path.split(separator: ";") {
                    let dir = URL(fileURLWithPath: String(entry))
                    let candidate = dir.appendingPathComponent("swift.exe")
                    if fm.fileExists(atPath: candidate.path) {
                        return dir
                    }
                }
            }
            // 2) Swift 6.3.x Windows installer 처럼 `swift.exe` 가 `%PATH%` 가
            //    아니라 `App Paths` 레지스트리에만 등록된 경우 PATH 스캔이 실패한다.
            //    `where.exe` 는 CreateProcess 와 동일하게 App Paths / PATHEXT 까지
            //    참조하므로 폴백으로 사용한다.
            return locateViaWhereExe("swift.exe", fm: fm)
        }

        /// `%SystemRoot%\System32\where.exe <name>` 의 첫 줄에서 디렉터리를
        /// 추출한다. 어떤 실패든 nil 로 흡수 — 상위 `stage()` 가 미해결 DLL
        /// 경고를 별도로 출력한다.
        private static func locateViaWhereExe(_ name: String, fm: FileManager) -> URL? {
            let systemRoot =
                ProcessInfo.processInfo.environment["SystemRoot"]
                ?? "C:\\Windows"
            let whereExe = URL(fileURLWithPath: systemRoot)
                .appendingPathComponent("System32/where.exe")
            guard fm.fileExists(atPath: whereExe.path) else { return nil }

            let proc = Process()
            proc.executableURL = whereExe
            proc.arguments = [name]
            let outPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                return nil
            }
            guard proc.terminationStatus == 0 else { return nil }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard let out = String(data: data, encoding: .utf8) else { return nil }
            let firstLine =
                out.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
                .first.map(String.init) ?? ""
            let exePath = firstLine.trimmingCharacters(in: .whitespaces)
            if exePath.isEmpty { return nil }
            let dir = URL(fileURLWithPath: exePath).deletingLastPathComponent()
            return fm.fileExists(atPath: dir.path) ? dir : nil
        }
    #endif

    // MARK: - Copy helpers

    private static func findDLL(named name: String, in dirs: [URL], fm: FileManager) -> URL? {
        for dir in dirs {
            let candidate = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Build-output convenience

    /// `KSWebView2Provisioner.stageLoaderDLL` 과 동일한 규칙으로 SwiftPM
    /// 빌드 디렉터리를 찾아, 그 안의 모든 `*.exe` 에 대해 `stage` 를 실행한다.
    ///
    /// - Parameters:
    ///   - cwd: 컨슈머 프로젝트 루트.
    ///   - configuration: `"debug"` 또는 `"release"`.
    /// - Returns: 모든 EXE 에 걸쳐 staging 된 총 DLL 개수.
    @discardableResult
    public static func stageBuildOutputs(cwd: URL, configuration: String) throws -> Int {
        #if os(Windows)
            let fm = FileManager.default
            #if arch(arm64)
                let hostTriple = "aarch64-unknown-windows-msvc"
            #else
                let hostTriple = "x86_64-unknown-windows-msvc"
            #endif

            let buildDir = cwd.appendingPathComponent(".build")
            var candidateDirs: [URL] = [
                buildDir.appendingPathComponent(hostTriple).appendingPathComponent(configuration)
            ]
            // 동일 체크아웃을 다른 triple 로도 빌드한 경우 함께 처리.
            let otherTriples = [
                "x86_64-unknown-windows-msvc",
                "aarch64-unknown-windows-msvc",
            ].filter { $0 != hostTriple }
            for triple in otherTriples {
                let p = buildDir.appendingPathComponent(triple).appendingPathComponent(configuration)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: p.path, isDirectory: &isDir), isDir.boolValue {
                    candidateDirs.append(p)
                }
            }

            var total = 0
            for dir in candidateDirs {
                guard
                    let entries = try? fm.contentsOfDirectory(
                        at: dir, includingPropertiesForKeys: nil)
                else { continue }
                for entry in entries where entry.pathExtension.lowercased() == "exe" {
                    total += try stage(executable: entry, destination: dir)
                }
            }
            return total
        #else
            _ = cwd
            _ = configuration
            return 0
        #endif
    }

    /// `KSWebView2Provisioner.stageLoaderDLL` 과 동일한 size+mtime 휴리스틱.
    /// dest 가 source 이상의 mtime + 동일 크기일 때만 skip.
    private static func isUpToDate(source: URL, destination: URL, fm: FileManager) -> Bool {
        guard let srcAttrs = try? fm.attributesOfItem(atPath: source.path),
            let dstAttrs = try? fm.attributesOfItem(atPath: destination.path),
            let sSize = srcAttrs[.size] as? NSNumber,
            let dSize = dstAttrs[.size] as? NSNumber,
            sSize == dSize,
            let sMtime = srcAttrs[.modificationDate] as? Date,
            let dMtime = dstAttrs[.modificationDate] as? Date,
            dMtime >= sMtime
        else {
            return false
        }
        return true
    }
}
