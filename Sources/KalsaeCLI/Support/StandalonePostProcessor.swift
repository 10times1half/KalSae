internal import Foundation

/// Windows standalone 번들의 PE 리소스 주입 단계.
///
/// Phase 0/1에서는 파이프라인 진입점과 도구 가용성 검증을 먼저 고정한다.
/// 실제 RCDATA/RT_MANIFEST/ICON/VERSION 주입은 후속 단계에서 이 타입에
/// 구현을 누적한다.
internal enum KSStandalonePostProcessor {
    internal struct Report: Sendable {
        let warnings: [String]
        let loaderEmbedded: Bool
        let manifestEmbedded: Bool
        let assetsEmbedded: Bool
    }

    internal struct Options: Sendable {
        let executable: URL
        let appName: String
        let version: String
        let identifier: String
        let loaderDLL: URL?
        let manifestPath: URL?
        let iconPath: URL?
        let assetsZipPath: URL?
    }

    /// Standalone PE 후처리 단계를 실행한다.
    ///
    /// - Best effort 정책:
    ///   - 도구가 있으면 리소스 주입을 시도한다.
    ///   - 도구가 없거나 주입 실패 시 warning만 반환한다(패키징 자체는 성공).
    ///
    /// 현재 단계에서 수행하는 작업:
    /// 1. `ResourceHacker`가 있으면 `KWV2_LOADER_DLL` RCDATA 주입 시도
    /// 2. `ResourceHacker`가 있으면 RT_MANIFEST(1) 주입 시도
    /// 3. `rcedit`가 있으면 아이콘/버전 정보 주입 시도
    internal static func run(_ options: Options) -> Report {
        var warnings: [String] = []
        var loaderEmbedded = false
        var manifestEmbedded = false
        var assetsEmbedded = false
        let fm = FileManager.default

        guard fm.fileExists(atPath: options.executable.path) else {
            return Report(
                warnings: [
                    "Standalone post-process skipped: executable not found at \(options.executable.path)"
                ],
                loaderEmbedded: false,
                manifestEmbedded: false,
                assetsEmbedded: false)
        }

        #if os(Windows)
            let resourceHacker = findExecutable(named: "ResourceHacker")
            let rcedit = findExecutable(named: "rcedit")

            if resourceHacker == nil, rcedit == nil {
                warnings.append(
                    "Standalone post-process: no PE editor found (ResourceHacker/rcedit). "
                        + "Keeping external files as compatibility fallback."
                )
                return Report(
                    warnings: warnings,
                    loaderEmbedded: false,
                    manifestEmbedded: false,
                    assetsEmbedded: false)
            }

            if let resourceHacker {
                if let loaderDLL = options.loaderDLL,
                    fm.fileExists(atPath: loaderDLL.path)
                {
                    let args = [
                        "-open", options.executable.path,
                        "-save", options.executable.path,
                        "-action", "addoverwrite",
                        "-res", loaderDLL.path,
                        "-mask", "RCDATA,KWV2_LOADER_DLL,",
                    ]
                    if let warning = runToolBestEffort(
                        toolPath: resourceHacker.path,
                        toolName: "ResourceHacker",
                        args: args,
                        label: "embed WebView2Loader.dll as RCDATA")
                    {
                        warnings.append(warning)
                    } else {
                        loaderEmbedded = true
                    }
                } else {
                    warnings.append(
                        "Standalone post-process: loader DLL not found at expected path; RCDATA embedding skipped."
                    )
                }

                if let manifestPath = options.manifestPath,
                    fm.fileExists(atPath: manifestPath.path)
                {
                    let args = [
                        "-open", options.executable.path,
                        "-save", options.executable.path,
                        "-action", "addoverwrite",
                        "-res", manifestPath.path,
                        "-mask", "MANIFEST,1,",
                    ]
                    if let warning = runToolBestEffort(
                        toolPath: resourceHacker.path,
                        toolName: "ResourceHacker",
                        args: args,
                        label: "embed RT_MANIFEST")
                    {
                        warnings.append(warning)
                    } else {
                        manifestEmbedded = true
                    }
                }

                if let assetsZipPath = options.assetsZipPath,
                    fm.fileExists(atPath: assetsZipPath.path)
                {
                    let args = [
                        "-open", options.executable.path,
                        "-save", options.executable.path,
                        "-action", "addoverwrite",
                        "-res", assetsZipPath.path,
                        "-mask", "RCDATA,KSAS_ASSETS_ZIP,",
                    ]
                    if let warning = runToolBestEffort(
                        toolPath: resourceHacker.path,
                        toolName: "ResourceHacker",
                        args: args,
                        label: "embed frontend asset zip as RCDATA")
                    {
                        warnings.append(warning)
                    } else {
                        assetsEmbedded = true
                    }
                }
            } else {
                warnings.append(
                    "Standalone post-process: ResourceHacker not found; loader/manifest/assets embedding skipped."
                )
            }

            if let rcedit {
                if let iconPath = options.iconPath,
                    fm.fileExists(atPath: iconPath.path)
                {
                    let iconArgs = [
                        options.executable.path,
                        "--set-icon", iconPath.path,
                    ]
                    if let warning = runToolBestEffort(
                        toolPath: rcedit.path,
                        toolName: "rcedit",
                        args: iconArgs,
                        label: "set executable icon")
                    {
                        warnings.append(warning)
                    }
                }

                let versionArgs = [
                    options.executable.path,
                    "--set-file-version", options.version,
                    "--set-product-version", options.version,
                    "--set-version-string", "ProductName", options.appName,
                    "--set-version-string", "FileDescription", options.appName,
                    "--set-version-string", "ProductVersion", options.version,
                    "--set-version-string", "FileVersion", options.version,
                    "--set-version-string", "InternalName", options.identifier,
                    "--set-version-string", "OriginalFilename", "\(options.appName).exe",
                ]
                if let warning = runToolBestEffort(
                    toolPath: rcedit.path,
                    toolName: "rcedit",
                    args: versionArgs,
                    label: "set version metadata")
                {
                    warnings.append(warning)
                }
            } else {
                warnings.append(
                    "Standalone post-process: rcedit not found; icon/version metadata embedding skipped."
                )
            }
        #else
            warnings.append("Standalone post-process is currently implemented for Windows hosts only.")
        #endif

        return Report(
            warnings: warnings,
            loaderEmbedded: loaderEmbedded,
            manifestEmbedded: manifestEmbedded,
            assetsEmbedded: assetsEmbedded)
    }

    private static func runToolBestEffort(
        toolPath: String,
        toolName: String,
        args: [String],
        label: String
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = args

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                return "Standalone post-process: \(toolName) failed to \(label) (exit \(process.terminationStatus))."
            }
            return nil
        } catch {
            return "Standalone post-process: \(toolName) failed to \(label): \(error)"
        }
    }
}
