import ArgumentParser
import Foundation
import KalsaeCLICore
import KalsaeCore

// MARK: - Linux 패키징 (RFC-009)

extension BuildCommand {
    /// RFC-009 — `--linux` 플래그 진입점. 어느 호스트에서나 동작하는 emit-only
    /// 파이프라인. 실제 `.deb` / `.AppImage` 산출은 Linux 호스트의 외부 도구
    /// (`dpkg-deb`, `appimagetool`) 가 마무리한다.
    ///
    /// ## 설계 원칙
    /// - **emit-only**: 이 함수는 디스크에 파일 트리만 쓴다. OS별 바이너리 도구
    ///   (`dpkg-deb`, `appimagetool`) 는 Linux 호스트에서만 실행 가능하므로,
    ///   사용자가 최종 산출물을 만들도록 README 명령어를 출력한다.
    /// - **호스트 무관**: Windows/macOS에서도 실행 가능. 실제로 .so 가 포함되지
    ///   않으므로 크로스 컴파일 CI에서 유용하다.
    ///
    /// ## 지원 형식 (--linux-format)
    /// - `tarball`: 압축 tar 아카이브 (.tar.gz). 가장 단순하고 의존성 불필요.
    /// - `deb`: Debian/Ubuntu 패키지. `dpkg-deb` 필요 (Linux 호스트).
    /// - `appimage`: AppImage 번들. `appimagetool` 필요 (Linux 호스트, fuse).
    func runPackageLinux(
        config: KSConfig, info: AppInfo, cwd: URL, fm: FileManager
    ) throws {
        guard let exeArg = linuxExecutable else {
            throw ValidationError(
                "--linux requires --linux-executable <path to Linux ELF binary>. "
                    + "Build it first with: swift build -c release --product <YourApp>")
        }
        guard let arch = KSPackager.LinuxArchitecture(rawValue: linuxArch.lowercased()) else {
            throw ValidationError("--linux-arch must be 'x86_64' or 'aarch64' (got '\(linuxArch)').")
        }

        // 콤마 분리 형식 파싱. `all` 이 포함되면 모든 형식을 한꺼번에 생성한다.
        var formats: Set<KSPackager.LinuxFormat> = []
        for raw in linuxFormat.split(separator: ",") {
            let token = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if token == "all" {
                formats = Set(KSPackager.LinuxFormat.allCases)
                break
            }
            guard let f = KSPackager.LinuxFormat(rawValue: token) else {
                throw ValidationError(
                    "--linux-format token '\(token)' is invalid. Allowed: tarball, deb, appimage, all.")
            }
            formats.insert(f)
        }
        guard !formats.isEmpty else {
            throw ValidationError("--linux-format must contain at least one format.")
        }

        // ELF 바이너리 경로: CLI 인자 또는 기본 빌드 디렉터리.
        let exeURL = URL(fileURLWithPath: exeArg, relativeTo: cwd)
        // 출력 디렉터리: `--output` 이 없으면 `dist/linux-<App>-<ver>/` 에 생성.
        let outputDir =
            output.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
            ?? cwd.appendingPathComponent("dist/linux-\(info.appName)-\(info.version)")
        let iconURL: URL? = linuxIcon.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
        // 프론트엔드 dist: `--dist` 우선, 없으면 `kalsae.json build.frontendDist`.
        let frontendDistURL: URL? = {
            if let raw = dist, !raw.isEmpty {
                return URL(fileURLWithPath: raw, relativeTo: cwd)
            }
            let fallback = cwd.appendingPathComponent(config.build.frontendDist)
            return fm.fileExists(atPath: fallback.path) ? fallback : nil
        }()

        let opts = KSPackager.LinuxOptions(
            executablePath: exeURL,
            configPath: try resolveConfigURL(cwd: cwd, fm: fm),
            frontendDist: frontendDistURL,
            output: outputDir,
            appName: info.appName,
            version: info.version,
            identifier: info.identifier,
            architecture: arch,
            formats: formats,
            iconPath: iconURL,
            maintainer: linuxMaintainer)

        print(
            "📦  Packaging \(info.appName) Linux (\(formats.map { $0.rawValue }.sorted().joined(separator: "+"))) v\(info.version) → \(outputDir.path)"
        )
        if dryrun {
            print("   (dry-run: skipping file emission)")
            return
        }
        let report = try KSPackager.runLinux(opts)
        print(report.description)
        print("ℹ  Next steps: see \(outputDir.path)/README.md for the exact tar/dpkg-deb/appimagetool commands.")
    }
}
