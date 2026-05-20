/// WiX Toolset v3.14 자동 프로비저너.
///
/// `candle.exe` / `light.exe`를 PATH에서 찾고, 없으면 다음 캐시 경로에 받아둔다:
///   - 기본: `%LOCALAPPDATA%\Kalsae\WixTools314\`
///   - `useLocalToolsDir=true`: `<project>/.kalsae/tools/WixTools314/`
///
/// 다운로드 원본은 GitHub release의 `wix314-binaries.zip` (네이티브 단일 .exe
/// 묶음, .NET SDK 불필요). 이미 추출돼 있으면 skip한다.
///
/// Tauri의 `wix314-binaries.zip` 모델을 그대로 따른다.
public import Foundation

public enum KSWiXProvisioner {
    /// WiX v3.14 GitHub release URL.
    public static let downloadURL =
        "https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip"

    /// 결과.
    public struct Result: Sendable {
        public let candleURL: URL
        public let lightURL: URL
        /// 다운로드/추출이 실제로 일어났는지(true) vs PATH/cache hit (false).
        public let fetched: Bool
    }

    /// `candle.exe` + `light.exe` 위치를 보장한다.
    ///
    /// 우선순위:
    /// 1. PATH (사용자가 미리 설치)
    /// 2. 캐시 (`%LOCALAPPDATA%\Kalsae\WixTools314\` 또는 `<project>/.kalsae/tools/WixTools314/`)
    /// 3. 자동 다운로드 (`autoFetch == true`인 경우)
    public static func ensure(
        projectRoot: URL,
        autoFetch: Bool,
        useLocalToolsDir: Bool
    ) throws -> Result {
        // 1) PATH 우선
        if let candle = findExecutable(named: "candle"),
            let light = findExecutable(named: "light")
        {
            return Result(candleURL: candle, lightURL: light, fetched: false)
        }

        let cacheRoot = cacheDirectory(projectRoot: projectRoot, useLocalToolsDir: useLocalToolsDir)
        let candleCache = cacheRoot.appendingPathComponent("candle.exe")
        let lightCache = cacheRoot.appendingPathComponent("light.exe")
        let fm = FileManager.default
        if fm.fileExists(atPath: candleCache.path), fm.fileExists(atPath: lightCache.path) {
            return Result(candleURL: candleCache, lightURL: lightCache, fetched: false)
        }

        guard autoFetch else {
            throw ShellError.commandNotFound(
                "WiX Toolset v3 (candle.exe / light.exe)"
                    + " — install via `winget install WiXToolset.WiXToolset` or"
                    + " re-run with --auto-fetch-wix.")
        }

        try downloadAndExtract(into: cacheRoot)

        guard fm.fileExists(atPath: candleCache.path),
            fm.fileExists(atPath: lightCache.path)
        else {
            throw ShellError.message(
                "WiX download succeeded but candle.exe / light.exe were not"
                    + " found under \(cacheRoot.path).")
        }
        return Result(candleURL: candleCache, lightURL: lightCache, fetched: true)
    }

    // MARK: - 내부

    /// `useLocalToolsDir`에 따른 캐시 디렉터리 결정.
    public static func cacheDirectory(
        projectRoot: URL, useLocalToolsDir: Bool
    ) -> URL {
        if useLocalToolsDir {
            return
                projectRoot
                .appendingPathComponent(".kalsae")
                .appendingPathComponent("tools")
                .appendingPathComponent("WixTools314")
        }
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let local = env["LOCALAPPDATA"], !local.isEmpty {
            base = URL(fileURLWithPath: local)
        } else if let home = env["USERPROFILE"], !home.isEmpty {
            base = URL(fileURLWithPath: home).appendingPathComponent("AppData/Local")
        } else {
            base = FileManager.default.temporaryDirectory
        }
        return
            base
            .appendingPathComponent("Kalsae")
            .appendingPathComponent("WixTools314")
    }

    private static func downloadAndExtract(into dest: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        guard let url = URL(string: downloadURL) else {
            throw ShellError.message("Invalid WiX download URL: \(downloadURL)")
        }
        print("⬇️   WiX Toolset v3.14 — fetching into \(dest.path)…")
        let tmpRoot = fm.temporaryDirectory
            .appendingPathComponent("wix314-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpRoot) }

        let zipPath = tmpRoot.appendingPathComponent("wix314-binaries.zip")
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ShellError.message(
                "Failed to download WiX from \(downloadURL): \(error.localizedDescription)")
        }
        try data.write(to: zipPath, options: [.atomic])

        do {
            try KSZipArchiver.unzip(archive: zipPath, to: dest)
        } catch {
            throw ShellError.message("Failed to extract wix314-binaries.zip: \(error)")
        }
    }
}
