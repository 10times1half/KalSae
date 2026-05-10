/// `kalsae build --standalone` 가 사용하는 Resource Hacker 프로비저너.
///
/// `KSStandalonePostProcessor` 는 PE 리소스 (RCDATA / RT_MANIFEST / 아이콘 / 버전)
/// 를 임베드하기 위해 Resource Hacker 와 rcedit 두 가지 외부 도구를 사용한다.
/// rcedit 는 npm 으로 흔히 설치되지만 Resource Hacker 는 그렇지 않으므로,
/// 새 사용자가 `kalsae new` → `kalsae build --standalone` 을 실행했을 때
/// "ResourceHacker not found" 경고와 함께 사실상 standalone 이 동작하지 않는
/// 결과로 끝났다.
///
/// 이 프로비저너는 `WebView2Provisioner` 와 같은 패턴으로:
/// - 기본 사용자 캐시 (`%LOCALAPPDATA%\Kalsae\Tools\ResourceHacker\`) 또는
///   PATH 에서 ResourceHacker.exe 를 찾는다.
/// - 없을 때 `Scripts/fetch-resourcehacker.ps1` 을 실행해 자동으로 다운로드.
/// - 결과 경로를 반환한다 (post-processor 에 명시적으로 전달).
///
/// Windows 외 호스트에서는 모든 진입점이 no-op 이며 `nil` 을 반환한다.
public import Foundation

public enum KSResourceHackerProvisioner {
    /// 기본 사용자 캐시 경로.
    /// `Scripts/fetch-resourcehacker.ps1` 의 기본값과 일치해야 한다.
    public static func defaultCachePath() -> URL? {
        #if os(Windows)
            let env = ProcessInfo.processInfo.environment
            let base =
                env["LOCALAPPDATA"]
                ?? env["USERPROFILE"].map { "\($0)\\AppData\\Local" }
                ?? ""
            guard !base.isEmpty else { return nil }
            return URL(fileURLWithPath: base)
                .appendingPathComponent("Kalsae")
                .appendingPathComponent("Tools")
                .appendingPathComponent("ResourceHacker")
                .appendingPathComponent("ResourceHacker.exe")
        #else
            return nil
        #endif
    }

    /// PATH 와 사용자 캐시에서 ResourceHacker.exe 의 절대 경로를 찾는다.
    /// Windows 외 호스트에서는 항상 nil.
    public static func locate(fm: FileManager = .default) -> URL? {
        #if os(Windows)
            if let onPath = findExecutable(named: "ResourceHacker") {
                return onPath
            }
            if let cache = defaultCachePath(), fm.fileExists(atPath: cache.path) {
                return cache
            }
            return nil
        #else
            return nil
        #endif
    }

    /// ResourceHacker.exe 가 사용 가능하도록 보장한다. 이미 있으면 그 경로를 반환,
    /// 없고 `autoFetch` 가 true 면 `Scripts/fetch-resourcehacker.ps1` 을 실행해 설치 후 반환.
    /// `autoFetch` 가 false 이고 발견 실패 시 nil 을 반환한다 (호출자가 경고/에러 처리).
    /// Windows 외 호스트에서는 항상 nil.
    public static func ensure(
        cwd: URL,
        autoFetch: Bool,
        fm: FileManager = .default
    ) throws -> URL? {
        #if os(Windows)
            if let existing = locate(fm: fm) { return existing }
            guard autoFetch else { return nil }

            // fetch-resourcehacker.ps1 는 Kalsae 체크아웃 (Sources/CKalsaeWV2/include
            // 마커) 안에만 존재한다. 컨슈머 cwd → SwiftPM 체크아웃 순으로 탐색한다.
            guard let scriptRoot = discoverKalsaeRoot(cwd: cwd, fm: fm) else {
                return nil
            }
            let script =
                scriptRoot
                .appendingPathComponent("Scripts")
                .appendingPathComponent("fetch-resourcehacker.ps1")
            guard fm.fileExists(atPath: script.path) else { return nil }

            let shellName: String
            if findExecutable(named: "pwsh") != nil {
                shellName = "pwsh"
            } else if findExecutable(named: "powershell") != nil {
                shellName = "powershell"
            } else {
                return nil
            }

            print("⬇️  ResourceHacker not found — fetching for --standalone embed...")
            try shell(
                command: shellName,
                arguments: [
                    "-NoProfile", "-ExecutionPolicy", "Bypass",
                    "-File", script.path,
                ],
                in: cwd.path)
            return locate(fm: fm)
        #else
            return nil
        #endif
    }

    private static func discoverKalsaeRoot(cwd: URL, fm: FileManager) -> URL? {
        let marker = ["Scripts", "fetch-resourcehacker.ps1"]

        func hasMarker(_ url: URL) -> Bool {
            var probe = url
            for component in marker { probe.appendPathComponent(component) }
            return fm.fileExists(atPath: probe.path)
        }

        if hasMarker(cwd) { return cwd }

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
                return child
            }
        }
        return nil
    }
}
