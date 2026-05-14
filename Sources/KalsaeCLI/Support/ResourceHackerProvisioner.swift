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
/// - 없을 때 angusj.com 공식 zip 을 다운로드해 캐시에 추출한다 (인-프로세스 Swift).
/// - 결과 경로를 반환한다 (post-processor 에 명시적으로 전달).
///
/// Windows 외 호스트에서는 모든 진입점이 no-op 이며 `nil` 을 반환한다.
public import Foundation

public enum KSResourceHackerProvisioner {
    /// 기본 사용자 캐시 경로 (`%LOCALAPPDATA%\Kalsae\Tools\ResourceHacker\ResourceHacker.exe`).
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
    /// 없고 `autoFetch` 가 true 면 직접 다운로드 + 추출해 설치 후 반환.
    /// 이전에는 `Scripts/fetch-resourcehacker.ps1` 을 PowerShell 로 실행했으나,
    /// PowerShell 의존성을 제거하기 위해 Swift 로 인라인 포팅됨.
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

            print("⬇️  ResourceHacker not found — fetching for --standalone embed...")
            try downloadAndInstall(fm: fm)
            return locate(fm: fm)
        #else
            return nil
        #endif
    }

    #if os(Windows)
        /// Resource Hacker 공식 zip 을 다운로드해 `defaultCachePath()` 위치에 추출.
        /// 추출된 zip 이 하위 디렉터리에 ResourceHacker.exe 를 포함할 수 있어
        /// 발견되면 캐시 루트로 끌어올린다.
        private static func downloadAndInstall(fm: FileManager) throws {
            guard let cache = defaultCachePath() else {
                throw ShellError.message("LOCALAPPDATA not set; cannot locate cache dir.")
            }
            let destDir = cache.deletingLastPathComponent()
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

            let downloadURLString = "https://www.angusj.com/resourcehacker/resource_hacker.zip"
            guard let downloadURL = URL(string: downloadURLString) else {
                throw ShellError.message("Failed to construct ResourceHacker URL.")
            }

            let tmpDir = fm.temporaryDirectory
                .appendingPathComponent("rh-\(UUID().uuidString)")
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmpDir) }

            let zipPath = tmpDir.appendingPathComponent("resource_hacker.zip")
            print("⬇️  Downloading Resource Hacker from \(downloadURLString)...")
            let data: Data
            do {
                data = try Data(contentsOf: downloadURL)
            } catch {
                throw ShellError.message(
                    "Failed to download ResourceHacker: \(error.localizedDescription)")
            }
            try data.write(to: zipPath, options: [.atomic])

            do {
                try KSZipArchiver.unzip(archive: zipPath, to: destDir)
            } catch {
                throw ShellError.message("Failed to extract ResourceHacker zip: \(error)")
            }

            // 만약 zip 안에 하위 디렉터리로 nested 되어 있으면 평탄화.
            if !fm.fileExists(atPath: cache.path) {
                if let found = locateExe(in: destDir, fm: fm) {
                    try fm.copyItem(at: found, to: cache)
                }
            }
            guard fm.fileExists(atPath: cache.path) else {
                throw ShellError.message(
                    "ResourceHacker.exe not found after extraction in \(destDir.path).")
            }
            print("✓  ResourceHacker installed: \(cache.path)")
        }

        /// `root` 하위에서 ResourceHacker.exe 를 재귀 탐색.
        private static func locateExe(in root: URL, fm: FileManager) -> URL? {
            guard
                let enumerator = fm.enumerator(
                    at: root, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles])
            else { return nil }
            for case let url as URL in enumerator
            where url.lastPathComponent.lowercased() == "resourcehacker.exe" {
                return url
            }
            return nil
        }
    #endif
}
