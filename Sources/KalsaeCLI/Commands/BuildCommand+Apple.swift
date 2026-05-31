// MARK: - macOS/iOS 패키징 (Apple 전용)

#if os(macOS)
    import ArgumentParser
    import Foundation
    import KalsaeCLICore
    import KalsaeCore

    extension BuildCommand {
        /// macOS .app 번들 패키징 (일반 `kalsae build`, `--store devid`, `--store mas` 공통 경로).
        ///
        /// ## 함수가 처리하는 작업
        /// 1. `.build/<configuration>/` 에서 실행 바이너리 위치 확인
        /// 2. frontend dist URL 해석 (sync 경로와 동일한 `resolveDistURL` 사용)
        /// 3. `KSPackager.MacOptions` 구성 → arch, codesign, notarization, entitlements, MAS 등 포함
        /// 4. `KSPackager.runMac(opts)` 호출로 실제 번들 생성
        ///
        /// ## universal 바이너리
        /// `--arch universal` 이면 x86_64 + arm64 fat binary 생성. 두 아키텍처의
        /// 빌드가 모두 `.build/` 에 존재해야 한다 (별도 swift build 필요).
        func runPackageMacOS(
            configuration: String, configURL: URL,
            info: AppInfo, cwd: URL, fm: FileManager
        ) throws {
            // arch 매핑: --arch x64/x86 → x86_64, arm64 → arm64, "universal" 새로 허용.
            let archEnum: KSPackager.MacArchitecture
            switch arch.lowercased() {
            case "arm64": archEnum = .arm64
            case "x64", "x86_64", "x86-64": archEnum = .x86_64
            case "universal": archEnum = .universal
            default:
                throw ValidationError("--arch on macOS must be: arm64 | x86_64 | universal (got '\(arch)')")
            }

            let expectedExePaths = builtExecutableCandidates(
                cwd: cwd,
                configuration: configuration,
                executableName: info.executableName,
                executableExtension: nil,
                fm: fm)
            guard let exeURL = resolveBuiltExecutableURL(
                cwd: cwd,
                configuration: configuration,
                executableName: info.executableName,
                executableExtension: nil,
                fm: fm)
            else {
                throw ValidationError(
                    "Built executable not found. Checked: "
                        + expectedExePaths.map(\.path).joined(separator: "; ")
                        + ". Did the build succeed?")
            }

            // dist 해석은 sync 경로와 동일한 헬퍼를 써 cwd 기준 일관성 보장 (Windows와 동일).
            let distURL: URL? = {
                let resolved = KSBuildPlan.resolveDistURL(
                    config: config, configURL: configURL, cwd: cwd, distOverride: dist)
                return fm.fileExists(atPath: resolved.path) ? resolved : nil
            }()

            // 출력 디렉터리는 `--output` 이 있으면 존중, 없으면 `dist/<App>-<ver>-<arch>/`.
            let outputURL: URL = {
                if let o = output {
                    return URL(fileURLWithPath: o, relativeTo: cwd)
                }
                return cwd.appendingPathComponent(
                    "dist/\(info.appName)-\(info.version)-\(archEnum.rawValue)")
            }()
            try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

            let opts = KSPackager.MacOptions(
                executablePath: exeURL,
                configPath: configURL,
                frontendDist: distURL,
                output: outputURL,
                appName: info.appName,
                version: info.version,
                identifier: info.identifier,
                architecture: archEnum,
                iconPath: icon.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
                codesignIdentity: codesignIdentity,
                zip: zip,
                stripSourceMaps: config.build.stripSourceMaps,
                stripExtensions: config.build.stripExtensions,
                distributionTarget: resolveDistributionTarget(config: config),
                notarytoolProfile: notarytoolProfile,
                entitlementsPath: entitlements.map { URL(fileURLWithPath: $0, relativeTo: cwd) },
                signDryRun: dryrun,
                installerSigningIdentity: installerIdentity,
                provisionProfilePath: provisionProfile.map {
                    URL(fileURLWithPath: $0, relativeTo: cwd)
                },
                masEntitlementsInput: resolveDistributionTarget(config: config) == .macAppStore
                    ? makeEntitlementsInput(config: config, target: .macAppStore)
                    : nil)

            print("📦  Packaging \(info.appName).app v\(info.version) (\(archEnum.rawValue))")
            let report = try KSPackager.runMac(opts)
            print(report.description)
        }

        /// iOS App Store IPA 패키징 (RFC-008 P4). macOS + Xcode 필수.
        ///
        /// `--store ios-appstore` 가 지정되고 macOS 호스트에서만 실행된다.
        /// xcodebuild archive → exportArchive 2단계를 거쳐 IPA를 생성한다.
        ///
        /// ## 의존성
        /// - macOS + Xcode 15+
        /// - `kalsae.json`에 `distribution.appleTeamID` 필요
        /// - `--ios-project` (.xcodeproj / .xcworkspace)
        /// - `--ios-scheme` (Xcode scheme 이름)
        ///
        /// ## 자동 생성 파일
        /// - `ExportOptions.plist`: method, teamID, signingStyle 자동 생성
        /// - `*.xcarchive`: xcodebuild archive 산출물
        /// - `*.ipa`: exportArchive 최종 결과
        func runPackageIOS(
            config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager
        ) throws {
            guard let projectArg = iosProject else {
                throw ValidationError(
                    "--store ios-appstore requires --ios-project <path to .xcodeproj or .xcworkspace>.")
            }
            guard let scheme = iosScheme, !scheme.isEmpty else {
                throw ValidationError(
                    "--store ios-appstore requires --ios-scheme <Xcode scheme name>.")
            }
            guard let teamID = config.distribution.appleTeamID, !teamID.isEmpty else {
                throw ValidationError(
                    "--store ios-appstore requires distribution.appleTeamID in kalsae.json.")
            }
            guard let method = KSPackager.IOSExportMethod(rawValue: iosExportMethod) else {
                throw ValidationError(
                    "--ios-export-method must be one of: "
                        + "app-store-connect | app-store | ad-hoc | enterprise | development.")
            }

            let projectURL = URL(fileURLWithPath: projectArg, relativeTo: cwd)
            let kind: KSPackager.IOSProjectKind =
                projectArg.hasSuffix(".xcworkspace")
                ? .xcworkspace(projectURL) : .xcodeproj(projectURL)

            let buildBase = cwd.appendingPathComponent(
                "dist/ios-\(info.appName)-\(info.version)")
            try fm.createDirectory(at: buildBase, withIntermediateDirectories: true)
            let archivePath = buildBase.appendingPathComponent("\(info.appName).xcarchive")
            let exportPath = buildBase.appendingPathComponent("export")
            let exportOptionsURL = buildBase.appendingPathComponent("ExportOptions.plist")
            let ipaURL = exportPath.appendingPathComponent("\(info.appName).ipa")

            // exportOptions.plist 생성. signingStyle은 --codesign-identity 유무로
            // "automatic" / "manual" 을 결정한다.
            let plistXML = KSPackager.renderIOSExportOptionsPlist(
                method: method,
                teamID: teamID,
                bundleIdentifier: info.identifier,
                signingStyle: codesignIdentity == nil ? "automatic" : "manual")
            try plistXML.write(to: exportOptionsURL, atomically: true, encoding: .utf8)

            let input = KSPackager.IOSPackagingInput(
                project: kind,
                scheme: scheme,
                archivePath: archivePath,
                exportPath: exportPath,
                exportOptionsPlist: exportOptionsURL,
                ipaOutput: ipaURL,
                teamID: teamID,
                bundleIdentifier: info.identifier,
                exportMethod: method,
                appStoreConnectAPIKeyID: ascKey,
                appStoreConnectAPIIssuerID: ascIssuer,
                codeSignIdentity: codesignIdentity,
                provisioningProfileSpecifier: provisionProfile)

            // 파이프라인: archive → export → (선택) upload
            let steps = KSPackager.planIOSPackagingPipeline(input)
            print(
                "🍎  iOS App Store pipeline (\(steps.count) step(s)) → "
                    + ipaURL.path)
            var warnings: [String] = []
            try KSPackager.executeIOSSteps(steps, dryRun: dryrun, warnings: &warnings)
            for w in warnings { print("⚠  \(w)") }
        }
    }
#endif
