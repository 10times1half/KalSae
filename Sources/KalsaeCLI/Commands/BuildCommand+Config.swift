// MARK: - 설정/헬퍼 함수

import ArgumentParser
import Foundation
import KalsaeCLICore
import KalsaeCore

extension BuildCommand {
    /// 앱 식별에 필요한 최소 메타데이터 구조체.
    /// `KSConfig.app` 에서 추출하며, `--target` 이 있으면 executableName 을 override 한다.
    struct AppInfo {
        let appName: String
        let version: String
        let identifier: String
        let executableName: String
    }

    // MARK: - 타이밍 출력

    /// 빌드 단계별 wall-clock 타이밍을 콘솔 및/또는 JSON 파일로 출력한다.
    /// - `--timings` (기본 ON): 사람이 읽기 쉬운 요약을 stdout에 출력
    /// - `--timings-json <path>`: CI 파싱 가능한 JSON을 지정 경로에 저장
    ///
    /// JSON 저장 실패는 ValidationError로 hard-fail — 빌드 산출물은 이미 있지만
    /// 사용자가 명시적으로 요청한 기능이므로 알림이 필요하다.
    func emitTimings(_ timer: KSBuildTimings, cwd: URL) throws {
        if timings {
            print(timer.summary())
        }
        guard let rel = timingsJson, !rel.isEmpty else { return }
        let url = URL(fileURLWithPath: rel, relativeTo: cwd)
        do {
            let data = try timer.jsonData()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            print("📝  Timings written to \(url.path)")
        } catch {
            // 사용자가 명시적으로 --timings-json 을 지정했으므로 실패는 hard error.
            // 빌드 산출물은 이미 생성된 시점이지만, 사용자에게 보고 실패를 분명히 알려야 한다.
            throw ValidationError(
                "Failed to write timings JSON to \(url.path): \(error)")
        }
    }

    // MARK: - Clean

    /// `--clean`: `.build/` 및 `dist/` 디렉터리를 재귀 삭제한다.
    /// dryrun 모드에서는 실제 삭제 없이 로그만 출력한다.
    func runClean(cwd: URL, fm: FileManager) throws {
        let buildDir = cwd.appendingPathComponent(".build")
        let distDir = cwd.appendingPathComponent("dist")
        for url in [buildDir, distDir] {
            guard fm.fileExists(atPath: url.path) else { continue }
            print("🧹  Removing \(url.path)")
            if dryrun { continue }
            try fm.removeItem(at: url)
        }
    }

    // MARK: - 설정 파일 로딩

    /// `kalsae.json` 의 절대 경로를 결정한다.
    /// - `--config <path>` 가 있으면 해당 경로를 우선 사용 (존재하지 않으면 에러).
    /// - 없으면 `KSConfigLocator.find()` 로 상위 디렉터리까지 검색.
    /// - 그래도 없으면 에러 (프로젝트 루트에 kalsae.json 필요).
    func resolveConfigURL(cwd: URL, fm: FileManager) throws -> URL {
        if let c = config {
            let url = URL(fileURLWithPath: c, relativeTo: cwd)
            guard fm.fileExists(atPath: url.path) else {
                throw ValidationError("Config file not found at \(url.path).")
            }
            return url
        }
        if let found = KSConfigLocator.find(cwd: cwd, fm: fm) {
            return found
        }
        throw ValidationError("Could not find kalsae.json (use --config to override).")
    }

    /// URL에서 `KSConfig` 객체를 로드한다.
    /// JSON 파싱 또는 스키마 검증 실패는 ValidationError 로 감싸 사용자에게 표시.
    func loadConfig(configURL: URL) throws -> KSConfig {
        do {
            return try KSConfigLoader.load(from: configURL)
        } catch {
            throw ValidationError(
                "Failed to load \(configURL.lastPathComponent): \(error)")
        }
    }

    // MARK: - Build output resolution

    /// `swift build` 산출물에서 실행 파일 경로 후보를 생성한다.
    ///
    /// SwiftPM은 환경에 따라 다음 두 형태 중 하나로 실행 파일을 배치한다.
    /// - `.build/<configuration>/<exe>`
    /// - `.build/<triple>/<configuration>/<exe>`
    ///
    /// 따라서 패키저는 두 경로 패턴을 모두 확인해야 한다.
    func builtExecutableCandidates(
        cwd: URL,
        configuration: String,
        executableName: String,
        executableExtension: String?,
        fm: FileManager
    ) -> [URL] {
        let filename: String = {
            guard let ext = executableExtension, !ext.isEmpty else { return executableName }
            return "\(executableName).\(ext)"
        }()

        var candidates: [URL] = [
            cwd
                .appendingPathComponent(".build")
                .appendingPathComponent(configuration)
                .appendingPathComponent(filename)
        ]

        let buildRoot = cwd.appendingPathComponent(".build")
        if let children = try? fm.contentsOfDirectory(
            at: buildRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        {
            for child in children {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }
                candidates.append(
                    child
                        .appendingPathComponent(configuration)
                        .appendingPathComponent(filename))
            }
        }

        var seen = Set<String>()
        var deduped: [URL] = []
        for candidate in candidates {
            let key = candidate.standardizedFileURL.path.lowercased()
            if seen.insert(key).inserted {
                deduped.append(candidate.standardizedFileURL)
            }
        }
        return deduped
    }

    /// 빌드 산출물에서 첫 번째로 존재하는 실행 파일 경로를 반환한다.
    func resolveBuiltExecutableURL(
        cwd: URL,
        configuration: String,
        executableName: String,
        executableExtension: String?,
        fm: FileManager
    ) -> URL? {
        builtExecutableCandidates(
            cwd: cwd,
            configuration: configuration,
            executableName: executableName,
            executableExtension: executableExtension,
            fm: fm
        ).first(where: { fm.fileExists(atPath: $0.path) })
    }

    // MARK: - Capability 검증

    /// `--capability-check` 모드에 따라 capability 대 선언된 `@KSCommand` 의
    /// 커맨드 목록을 비교한다.
    ///
    /// - `strict`: 누락된 capability가 하나라도 있으면 빌드 중단
    /// - `warn` (기본): 누락 항목을 로그로만 출력, 빌드 계속
    /// - `off`: 검증 자체를 건너뜀
    ///
    /// `KSBindingsGenerator`가 Sources/ 디렉터리를 스캔해 `@KSCommand` 매크로가
    /// 붙은 함수들을 수집하고, 그 이름들을 `config.capabilities` 와 대조한다.
    func runCapabilityValidation(config: KSConfig, cwd: URL) throws {
        guard let mode = KSCapabilityValidator.Mode(rawValue: capabilityCheck) else {
            throw ValidationError(
                "--capability-check must be one of: strict | warn | off. Got '\(capabilityCheck)'.")
        }
        if mode == .off { return }

        let sources = KSBindingsGenerator.discoverSwiftFiles(
            under: cwd.appendingPathComponent("Sources"))
        let commands = KSBindingsGenerator.scanCommands(in: sources)
        let report = KSCapabilityValidator.validate(
            capabilities: config.capabilities, commands: commands)

        if report.findings.isEmpty {
            return
        }
        print("🛡  capability validator findings:")
        for f in report.findings {
            print("   \(f.description)")
        }
        if report.shouldFail(in: mode) {
            throw ValidationError(
                "Capability validation failed (mode: \(mode.rawValue)). "
                    + "Fix the errors above or rerun with --capability-check off.")
        }
    }

    // MARK: - 프론트엔드 빌드

    /// `kalsae.json build.buildCommand` 가 설정된 경우 해당 셸 명령을 실행한다.
    /// `--skip-frontend` 가 true 이거나 buildCommand 가 비어있으면 아무 일도 하지 않는다.
    func runFrontendBuildIfNeeded(config: KSConfig, cwd: URL) throws {
        guard let raw = KSBuildPlan.normalizedCommand(config.build.buildCommand) else {
            return
        }
        print("🧩  Running frontend build command: \(raw)")
        try shell(commandLine: raw, in: cwd.path)
    }

    // MARK: - 프론트엔드 dist 검증

    /// dist 디렉터리가 유효한지 검증한다.
    /// - `--allow-missing-dist` 가 없고 dist 가 비어있거나 없으면 에러.
    /// - `--bundle-report` 가 kalsae.json 에 설정된 경우 번들 분석 리포트 출력.
    func validateFrontendDist(
        config: KSConfig,
        configURL: URL,
        cwd: URL,
        fm: FileManager
    ) throws {
        let distURL = KSBuildPlan.resolveDistURL(
            config: config,
            configURL: configURL,
            cwd: cwd,
            distOverride: dist)
        do {
            try KSBuildPlan.validateFrontendDist(
                at: distURL,
                allowMissingDist: allowMissingDist,
                fm: fm)
        } catch let error as KSBuildPlanError {
            throw ValidationError(error.description)
        }

        // 번들 분석 리포트 (bundleReport 옵션이 true일 때)
        if config.build.bundleReport {
            let report = KSBundleAnalyzer.analyze(distURL: distURL)
            print(report.description)
        }
    }

    // MARK: - WebView2 사전 조건

    /// WebView2 SDK가 빌드에 필요한지 확인한다.
    ///
    /// Windows 전용: Headless 브라우징을 위해 C++ shim(`CKalsaeWV2`)이
    /// WebView2 헤더를 필요로 한다. `Vendor/WebView2/` 가 없으면
    /// `--auto-fetch-webview2` (기본 ON) 에 따라 자동 다운로드한다.
    /// fetch 스크립트는 `Scripts/fetch-webview2.ps1` 이다.
    func validateWebView2Preconditions(cwd: URL, fm: FileManager) throws {
        #if os(Windows)
            do {
                try KSWebView2Provisioner.ensure(
                    cwd: cwd,
                    autoFetch: autoFetchWebView2,
                    sdkVersion: webview2SdkVersion)
            } catch let error as ShellError {
                throw ValidationError(error.description)
            }
        #endif
    }

    // MARK: - 리소스 동기화

    /// Returns `true` when any file was copied or removed. The parallel build
    /// path uses this to decide whether to re-run `swift build` to refresh
    /// the bundled `Resources/` (Phase 2 finalize pass).
    ///
    /// 실제 sync 로직은 `KSResourceSyncManager` 로 분리되어 있다 — 본 함수는
    /// CLI 옵션 (`--sync-resources`, `--target`, `--dist`) 을 dist/Resources URL
    /// 한 쌍으로 해석하고 결과를 사용자 친화적 메시지로 출력하는 책임만 진다.
    ///
    /// ## 동기화 규칙
    /// 1. dist/ 의 모든 파일을 Sources/<Target>/Resources/ 로 복사
    /// 2. `build.preserveResources` 에 매칭되는 파일은 제거하지 않음 (preserve globs)
    /// 3. `--no-prune` 이 없으면 dist 에 없는 파일(orphan)들을 Resources/ 에서 삭제
    /// 4. 데모 앱 등 dist == Resources 인 경우 경고 메시지를 출력하고 건너뜀
    @discardableResult
    func syncFrontendResourcesIfNeeded(
        config: KSConfig,
        configURL: URL,
        cwd: URL,
        fm: FileManager
    ) throws -> Bool {
        guard syncResources else { return false }

        let distURL = KSBuildPlan.resolveDistURL(
            config: config,
            configURL: configURL,
            cwd: cwd,
            distOverride: dist)

        let executableName = target ?? config.app.name
        let resourcesURL =
            cwd
            .appendingPathComponent("Sources")
            .appendingPathComponent(executableName)
            .appendingPathComponent("Resources")

        let report = try KSResourceSyncManager.sync(
            distURL: distURL,
            resourcesURL: resourcesURL,
            preservedGlobs: config.build.preserveResources,
            noPrune: noPrune,
            fm: fm)

        if let reason = report.skippedReason {
            // 데모처럼 dist 와 Resources/ 가 겹치는 합법적 케이스 — 건너뛴 이유를 안내.
            if reason.contains("overlaps") {
                print(
                    "ℹ  Skipping resource sync: \(reason). "
                        + "Configure `build.frontendDist` to a separate directory to enable sync.")
            }
            return false
        }

        if report.copied == 0 && report.skipped > 0 && report.removed == 0 {
            print("📁  Frontend dist already in sync (\(report.skipped) files unchanged)")
        } else {
            print(
                "📁  Synced frontend dist to \(resourcesURL.path) "
                    + "(\(report.copied) copied, \(report.skipped) unchanged, "
                    + "\(report.removed) removed)")
        }
        if !report.removedRels.isEmpty {
            // 최초 N 개만 보여주어 출력 길이를 제한한다 — 사용자가 의도치 않게
            // 잃은 파일이 있는지 확인하는 디버그 보조 정보.
            let preview = report.removedRels.prefix(10)
            for rel in preview {
                print("    - \(rel)")
            }
            let remaining = report.removedRels.count - preview.count
            if remaining > 0 {
                print("    … and \(remaining) more")
            }
        }
        if noPrune {
            print(
                "ℹ  --no-prune: orphan removal skipped. "
                    + "Re-run without --no-prune to clean stale resources.")
        }
        if report.failed > 0 {
            print("⚠  Failed to copy \(report.failed) file(s) during sync.")
        }
        return report.didMutate
    }

    /// `kalsae.json`에서 패키징에 필요한 메타데이터만 파싱한다.
    /// `KalsaeCore.KSConfig`를 재사용하여 스키마가 런타임 로더와
    /// 동기화된 상태를 유지한다 — 수동 CLI 파서와
    /// 엔진 관점 사이의 관점 차이가 없다.
    func parseAppInfo(config: KSConfig) -> AppInfo {
        let exec = target ?? config.app.name
        return AppInfo(
            appName: config.app.name,
            version: config.app.version,
            identifier: config.app.identifier,
            executableName: exec)
    }
}
