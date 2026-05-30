/// `kalsae build --standalone` 가 사용하는 rcedit 프로비저너.
///
/// standalone 후처리에서 아이콘/버전 메타데이터 주입은 여전히 rcedit 에
/// 의존한다. PATH 에 없을 때 사용자가 매번 수동 설치하지 않아도 되도록
/// ResourceHacker 와 동일한 패턴으로 사용자 캐시에 단일 실행 파일을 내려받아
/// 재사용한다.

public import Foundation

public enum KSRceditProvisioner {
    /// 기본 사용자 캐시 경로 (`%LOCALAPPDATA%\Kalsae\Tools\rcedit\rcedit-x64.exe`).
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
                .appendingPathComponent("rcedit")
                .appendingPathComponent("rcedit-x64.exe")
        #else
            return nil
        #endif
    }

    /// PATH 와 사용자 캐시에서 rcedit 의 절대 경로를 찾는다.
    public static func locate(fm: FileManager = .default) -> URL? {
        #if os(Windows)
            if let onPath = findExecutable(named: "rcedit") {
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

    /// rcedit 가 사용 가능하도록 보장한다. 이미 있으면 그 경로를 반환하고,
    /// 없고 `autoFetch` 가 true 면 GitHub release 바이너리를 캐시에 설치한다.
    public static func ensure(
        cwd: URL,
        autoFetch: Bool,
        fm: FileManager = .default
    ) throws -> URL? {
        #if os(Windows)
            _ = cwd
            if let existing = locate(fm: fm) { return existing }
            guard autoFetch else { return nil }

            print("⬇️  rcedit not found — fetching for --standalone metadata embed...")
            try downloadAndInstall(fm: fm)
            return locate(fm: fm)
        #else
            _ = cwd
            _ = autoFetch
            _ = fm
            return nil
        #endif
    }

    #if os(Windows)
        private static func downloadAndInstall(fm: FileManager) throws {
            guard let cache = defaultCachePath() else {
                throw ShellError.message("LOCALAPPDATA not set; cannot locate cache dir.")
            }
            let destDir = cache.deletingLastPathComponent()
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

            let downloadURLString =
                "https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe"
            guard let downloadURL = URL(string: downloadURLString) else {
                throw ShellError.message("Failed to construct rcedit download URL.")
            }

            print("⬇️  Downloading rcedit from \(downloadURLString)...")
            let data: Data
            do {
                data = try Data(contentsOf: downloadURL)
            } catch {
                throw ShellError.message(
                    "Failed to download rcedit: \(error.localizedDescription)")
            }

            try data.write(to: cache, options: [.atomic])
            guard fm.fileExists(atPath: cache.path) else {
                throw ShellError.message("rcedit was not written to \(cache.path).")
            }
            print("✓  rcedit installed: \(cache.path)")
        }
    #endif
}
