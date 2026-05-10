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
        let configEmbedded: Bool
        let runtimeEmbedded: Bool
        let iconEmbedded: Bool
        let versionEmbedded: Bool
        /// Windows host 이면서 ResourceHacker 와 rcedit 둘 다 PATH 에서
        /// 찾을 수 없을 때 true. 상위에서 standalone hard-error 판단에 사용.
        let toolsMissing: Bool
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
        /// Kalsae.json 경로. embed 을 원하면 주고, 아니면 nil.
        let configPath: URL?
        /// kalsae.runtime.json 경로. embed 을 원하면 주고, 아니면 nil.
        /// fixed runtime 정책에서는 외부 폴더 참조가 필요하므로 임베드를
        /// 스킵하고 nil 을 전달하는 것이 일반적.
        let runtimePath: URL?
        /// PATH 에 ResourceHacker 가 없더라도 명시적 경로를 주면 그 경로를
        /// 우선 사용한다 (KSResourceHackerProvisioner 결과).
        let resourceHackerOverride: URL?
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
        var configEmbedded = false
        var runtimeEmbedded = false
        var iconEmbedded = false
        var versionEmbedded = false
        // toolsMissing 은 PE \ud3b8\uc9d1\uae30 2\uac1c\uac00 \ubaa8\ub450 \uc5c6\ub294 \uc870\uae30 \ub9ac\ud134 \uacbd\ub85c\uc5d0\uc11c\ub9cc true.
        // \uadf8 \uc678 \uacbd\ub85c\ub294 \ubd84\uae30\uc5d0 \ub3c4\ub2ec\ud558\uc9c0 \uc54a\uc73c\ubbc0\ub85c \ucd5c\uc885 return \uc740 \uc0c1\uc218 false.
        let fm = FileManager.default

        guard fm.fileExists(atPath: options.executable.path) else {
            return Report(
                warnings: [
                    "Standalone post-process skipped: executable not found at \(options.executable.path)"
                ],
                loaderEmbedded: false,
                manifestEmbedded: false,
                assetsEmbedded: false,
                configEmbedded: false,
                runtimeEmbedded: false,
                iconEmbedded: false,
                versionEmbedded: false,
                toolsMissing: false)
        }

        #if os(Windows)
            let resourceHacker =
                options.resourceHackerOverride
                ?? findExecutable(named: "ResourceHacker")
            let rcedit = findExecutable(named: "rcedit")

            // 1차: in-process Win32 BeginUpdateResource API 로 RCDATA + RT_MANIFEST
            //     를 한 번에 주입한다. 외부 도구가 없어도 standalone embed 가
            //     동작하도록 보장하는 기본 경로.
            // 2차: 1차가 실패하면 ResourceHacker 가 있을 때 그 도구로 재시도.
            // 3차: 그래도 실패하면 외부 파일을 그대로 둔 호환성 폴백.
            do {
                var rcdataEntries: [(name: String, data: Data)] = []
                if let loaderDLL = options.loaderDLL,
                    fm.fileExists(atPath: loaderDLL.path),
                    let data = try? Data(contentsOf: loaderDLL)
                {
                    rcdataEntries.append((name: "KWV2_LOADER_DLL", data: data))
                }
                if let assetsZipPath = options.assetsZipPath,
                    fm.fileExists(atPath: assetsZipPath.path),
                    let data = try? Data(contentsOf: assetsZipPath)
                {
                    rcdataEntries.append((name: "KSAS_ASSETS_ZIP", data: data))
                }
                if let configPath = options.configPath,
                    fm.fileExists(atPath: configPath.path),
                    let data = try? Data(contentsOf: configPath)
                {
                    rcdataEntries.append((name: "KSAS_CONFIG_JSON", data: data))
                }
                if let runtimePath = options.runtimePath,
                    fm.fileExists(atPath: runtimePath.path),
                    let data = try? Data(contentsOf: runtimePath)
                {
                    rcdataEntries.append((name: "KSAS_RUNTIME_JSON", data: data))
                }
                var manifestData: Data?
                if let manifestPath = options.manifestPath,
                    fm.fileExists(atPath: manifestPath.path)
                {
                    manifestData = try? Data(contentsOf: manifestPath)
                }

                if !rcdataEntries.isEmpty || manifestData != nil {
                    do {
                        try KSPEResourcePatcher.update(
                            executable: options.executable,
                            rcdata: rcdataEntries,
                            manifest: manifestData)
                        for entry in rcdataEntries {
                            switch entry.name {
                            case "KWV2_LOADER_DLL": loaderEmbedded = true
                            case "KSAS_ASSETS_ZIP": assetsEmbedded = true
                            case "KSAS_CONFIG_JSON": configEmbedded = true
                            case "KSAS_RUNTIME_JSON": runtimeEmbedded = true
                            default: break
                            }
                        }
                        if manifestData != nil { manifestEmbedded = true }
                    } catch {
                        warnings.append(
                            "Standalone post-process: in-process PE patch failed (\(error)); "
                                + "trying ResourceHacker fallback if available.")
                    }
                }
            }

            // 2차 폴백: 1차에서 채우지 못한 항목만 ResourceHacker 로 재시도.
            if let resourceHacker,
                !loaderEmbedded || !manifestEmbedded || !assetsEmbedded || !configEmbedded
                    || !runtimeEmbedded
            {
                if !loaderEmbedded,
                    let loaderDLL = options.loaderDLL,
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
                }

                if !manifestEmbedded,
                    let manifestPath = options.manifestPath,
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

                if !assetsEmbedded,
                    let assetsZipPath = options.assetsZipPath,
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

                if !configEmbedded,
                    let configPath = options.configPath,
                    fm.fileExists(atPath: configPath.path)
                {
                    let args = [
                        "-open", options.executable.path,
                        "-save", options.executable.path,
                        "-action", "addoverwrite",
                        "-res", configPath.path,
                        "-mask", "RCDATA,KSAS_CONFIG_JSON,",
                    ]
                    if let warning = runToolBestEffort(
                        toolPath: resourceHacker.path,
                        toolName: "ResourceHacker",
                        args: args,
                        label: "embed Kalsae.json as RCDATA")
                    {
                        warnings.append(warning)
                    } else {
                        configEmbedded = true
                    }
                }

                if !runtimeEmbedded,
                    let runtimePath = options.runtimePath,
                    fm.fileExists(atPath: runtimePath.path)
                {
                    let args = [
                        "-open", options.executable.path,
                        "-save", options.executable.path,
                        "-action", "addoverwrite",
                        "-res", runtimePath.path,
                        "-mask", "RCDATA,KSAS_RUNTIME_JSON,",
                    ]
                    if let warning = runToolBestEffort(
                        toolPath: resourceHacker.path,
                        toolName: "ResourceHacker",
                        args: args,
                        label: "embed kalsae.runtime.json as RCDATA")
                    {
                        warnings.append(warning)
                    } else {
                        runtimeEmbedded = true
                    }
                }
            }

            // toolsMissing: in-process 패치 + ResourceHacker + rcedit 모두 없거나 실패.
            // 우리는 in-process 경로가 항상 시도되므로 사실상 도달 불가지만,
            // 하위 호환을 위해 rcedit 부재 + 모든 RCDATA/MANIFEST 미주입 + RH 없음
            // 경우만 hard-error 신호로 남긴다.
            let allEmbedSkipped =
                !loaderEmbedded && !manifestEmbedded && !assetsEmbedded && !configEmbedded
                && !runtimeEmbedded
            if resourceHacker == nil, rcedit == nil, allEmbedSkipped {
                warnings.append(
                    "Standalone post-process: no embed mechanism succeeded "
                        + "(in-process patcher failed and no PE editor on PATH).")
                return Report(
                    warnings: warnings,
                    loaderEmbedded: false,
                    manifestEmbedded: false,
                    assetsEmbedded: false,
                    configEmbedded: false,
                    runtimeEmbedded: false,
                    iconEmbedded: false,
                    versionEmbedded: false,
                    toolsMissing: true)
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
                    } else {
                        iconEmbedded = true
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
                } else {
                    versionEmbedded = true
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
            assetsEmbedded: assetsEmbedded,
            configEmbedded: configEmbedded,
            runtimeEmbedded: runtimeEmbedded,
            iconEmbedded: iconEmbedded,
            versionEmbedded: versionEmbedded,
            toolsMissing: false)
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
