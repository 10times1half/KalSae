/// Linux 배포 패키저 (RFC-009).
///
/// `swift build -c release` 로 빌드한 Linux ELF 실행 파일을 입력으로 받아
/// 다음 형식 중 하나 이상을 emit 한다:
///
/// - `tarball` : `<app>-<ver>-linux-<arch>/` 디렉터리 (외부에서 `tar -czf` 하면
///               배포 가능). 가장 가벼우며 어떤 배포판에도 동작.
/// - `deb`     : Debian 패키지 트리 (`DEBIAN/control` + `usr/*` FHS 레이아웃).
///               외부에서 `dpkg-deb --build <dir>` 실행하면 `.deb` 생성. Ubuntu /
///               Debian / Mint 대상 권장 형식. **시스템 GTK4 + WebKitGTK 6.0 를
///               `Depends:` 로 선언** — 별도 번들링 없음 (Kalsae 철학).
/// - `appImage`: AppDir 레이아웃 (`AppRun` + 루트 .desktop/.png + `usr/bin/<exe>`).
///               외부에서 `appimagetool <AppDir>` 실행하면 단일 `.AppImage`.
///               이식성은 가장 높으나 시스템 라이브러리도 포함되어 ~120MB 가
///               되므로 Kalsae 의 "OS 엔진 재사용" 철학과는 트레이드오프가 있음.
///
/// 본 패키저는 **어느 호스트 OS 에서도 실행 가능** (순수 파일 emit). 실제
/// `.deb` / `.AppImage` 산출은 호출자가 Linux 호스트에서 외부 도구 (`dpkg-deb`,
/// `appimagetool`, `tar`) 로 마무리한다. 이 패턴은 `runIOS` / `runAndroid` 와
/// 동일하다 (.app 번들 / Gradle 프로젝트만 emit 하고 실제 .ipa / .apk 는 macOS /
/// Android Studio 호스트에서 빌드).
public import Foundation
internal import KalsaeCore

extension KSPackager {

    public enum LinuxArchitecture: String, Sendable, CaseIterable {
        case x86_64
        case aarch64

        /// Debian `Architecture:` 필드 표기 (FHS / dpkg 관례).
        public var debArchitecture: String {
            switch self {
            case .x86_64: return "amd64"
            case .aarch64: return "arm64"
            }
        }
    }

    public enum LinuxFormat: String, Sendable, CaseIterable {
        case tarball
        case deb
        case appImage = "appimage"
    }

    public struct LinuxOptions: Sendable {
        /// 빌드된 Linux ELF 실행 파일 (예: `.build/release/MyApp`).
        public var executablePath: URL
        public var configPath: URL
        public var frontendDist: URL?
        public var output: URL
        public var appName: String
        public var version: String
        /// 역도메인 식별자 (예: `com.example.myapp`). .desktop / .deb 명명에 사용.
        public var identifier: String
        public var architecture: LinuxArchitecture
        public var formats: Set<LinuxFormat>
        public var iconPath: URL?
        /// `.deb` 의 `Maintainer:` 필드. `.deb` 가 요청되면 필수.
        public var maintainer: String?
        public var stripSourceMaps: Bool
        public var stripExtensions: [String]

        public init(
            executablePath: URL,
            configPath: URL,
            frontendDist: URL?,
            output: URL,
            appName: String,
            version: String,
            identifier: String,
            architecture: LinuxArchitecture = .x86_64,
            formats: Set<LinuxFormat> = [.tarball],
            iconPath: URL? = nil,
            maintainer: String? = nil,
            stripSourceMaps: Bool = true,
            stripExtensions: [String] = []
        ) {
            self.executablePath = executablePath
            self.configPath = configPath
            self.frontendDist = frontendDist
            self.output = output
            self.appName = appName
            self.version = version
            self.identifier = identifier
            self.architecture = architecture
            self.formats = formats
            self.iconPath = iconPath
            self.maintainer = maintainer
            self.stripSourceMaps = stripSourceMaps
            self.stripExtensions = stripExtensions
        }
    }

    // MARK: - 메인 진입점

    /// Linux 배포 산출물을 emit 한다. 호스트 OS 무관 — `.deb` / `.AppImage` 의
    /// 최종 binary 생성은 외부 도구 (`dpkg-deb`, `appimagetool`) 가 필요하다.
    public static func runLinux(_ opts: LinuxOptions) throws -> Report {
        let fm = FileManager.default
        var warnings: [String] = []

        // 0) 사전 검증
        guard !opts.formats.isEmpty else {
            throw KSError(
                code: .configInvalid,
                message: "Linux packager requires at least one format (tarball, deb, appImage).")
        }
        guard fm.fileExists(atPath: opts.executablePath.path) else {
            throw KSError(
                code: .configInvalid,
                message: "Linux executable not found at \(opts.executablePath.path). "
                    + "Build it first with: swift build -c release --product <YourApp>")
        }
        guard isValidLinuxIdentifier(opts.identifier) else {
            throw KSError(
                code: .configInvalid,
                message: "Linux identifier '\(opts.identifier)' is invalid. "
                    + "Must be reverse-DNS, e.g. com.example.myapp.")
        }
        if opts.formats.contains(.deb) {
            guard let m = opts.maintainer, !m.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw KSError(
                    code: .configInvalid,
                    message: "Linux .deb format requires --linux-maintainer 'Name <email>'.")
            }
            guard m.contains("<") && m.contains("@") && m.contains(">") else {
                throw KSError(
                    code: .configInvalid,
                    message: "Linux .deb maintainer must be 'Name <email@host>' (got '\(m)').")
            }
        }
        guard isValidDebVersion(opts.version) else {
            throw KSError(
                code: .configInvalid,
                message: "Linux version '\(opts.version)' is invalid for .deb "
                    + "(must start with a digit; allowed: digits, letters, '.', '+', '-', '~').")
        }

        // 1) 출력 디렉터리 (clean rebuild)
        if fm.fileExists(atPath: opts.output.path) {
            try retryingTransient { try fm.removeItem(at: opts.output) }
        }
        try fm.createDirectory(at: opts.output, withIntermediateDirectories: true)

        // Preserve the developer's build-output filename (e.g. SwiftPM product name)
        // instead of forcing a sanitized app-name. Falls back to a sanitized
        // app-name only when the source path has no usable basename.
        let exeName: String = {
            let base = opts.executablePath.lastPathComponent
            return base.isEmpty ? sanitizedLinuxExecutableName(opts.appName) : base
        }()
        var nextSteps: [String] = []

        // 2) Tarball: <output>/tarball/<app>-<ver>-linux-<arch>/
        if opts.formats.contains(.tarball) {
            let stageName = "\(slugify(opts.appName))-\(opts.version)-linux-\(opts.architecture.rawValue)"
            let stage = opts.output.appendingPathComponent("tarball").appendingPathComponent(stageName)
            try emitTarballTree(stage: stage, opts: opts, exeName: exeName, fm: fm, warnings: &warnings)
            nextSteps.append("tar -czf '\(stageName).tar.gz' -C '\(stage.deletingLastPathComponent().path)' '\(stageName)'")
        }

        // 3) Debian package tree: <output>/deb/<id>/{DEBIAN,usr}
        if opts.formats.contains(.deb) {
            let debRoot = opts.output.appendingPathComponent("deb").appendingPathComponent(opts.identifier)
            try emitDebTree(root: debRoot, opts: opts, exeName: exeName, fm: fm, warnings: &warnings)
            nextSteps.append("dpkg-deb --build '\(debRoot.path)' '\(opts.identifier)_\(opts.version)_\(opts.architecture.debArchitecture).deb'")
        }

        // 4) AppImage AppDir: <output>/AppDir/
        if opts.formats.contains(.appImage) {
            let appDir = opts.output.appendingPathComponent("AppDir")
            try emitAppImageTree(appDir: appDir, opts: opts, exeName: exeName, fm: fm, warnings: &warnings)
            warnings.append(
                "AppImage bundles GTK4/WebKitGTK system libraries (~120MB). "
                    + "Prefer .deb for the Kalsae 'reuse OS engine' philosophy when targeting Debian-based distros.")
            nextSteps.append("appimagetool '\(appDir.path)' '\(slugify(opts.appName))-\(opts.version)-\(opts.architecture.rawValue).AppImage'")
        }

        // 5) 호스트 OS 경고
        #if !os(Linux)
            warnings.append(
                "Emitted Linux package tree on non-Linux host. Run the 'next steps' commands "
                    + "below on a Linux machine (or in CI) to produce the final artifacts.")
        #endif

        // 6) 안내 README
        let readme = renderLinuxReadme(opts: opts, nextSteps: nextSteps)
        try readme.write(
            to: opts.output.appendingPathComponent("README.md"),
            atomically: true, encoding: .utf8)

        return Report(
            outputPath: opts.output.path,
            zipPath: nil,
            policy: "linux-\(opts.formats.map { $0.rawValue }.sorted().joined(separator: "+"))",
            warnings: warnings,
            standalone: nil)
    }

    // MARK: - Format emit (각 포맷은 self-contained 서브트리)

    /// Tarball staging: 단순한 평면 구조 — 실행 파일과 자원이 같은 디렉터리.
    ///
    /// ```
    /// <stage>/
    ///   <exe>
    ///   Resources/...           # frontend dist
    ///   kalsae.json             # frontendDist="Resources", devtools off
    ///   <appName>.desktop
    ///   <appName>.png           # icon (옵션)
    ///   INSTALL.md
    /// ```
    internal static func emitTarballTree(
        stage: URL,
        opts: LinuxOptions,
        exeName: String,
        fm: FileManager,
        warnings: inout [String]
    ) throws {
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)

        // exe
        let dstExe = stage.appendingPathComponent(exeName)
        try safeCopy(from: opts.executablePath, to: dstExe, fm: fm)
        markExecutableIfPossible(dstExe, fm: fm)

        // config (frontendDist="Resources", devtools off)
        let dstConfig = stage.appendingPathComponent("kalsae.json")
        try safeCopy(from: opts.configPath, to: dstConfig, fm: fm)
        try rewritePackagedConfig(at: dstConfig, frontendDist: "Resources", disableDevtools: true)

        // frontend dist → Resources/
        let resources = stage.appendingPathComponent("Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        if let dist = opts.frontendDist, fm.fileExists(atPath: dist.path) {
            try copyLinuxDistContents(of: dist, into: resources, fm: fm)
            let strip = KSBundleAnalyzer.strip(
                distURL: resources,
                stripSourceMaps: opts.stripSourceMaps,
                stripExtensions: opts.stripExtensions)
            if strip.failed > 0 {
                warnings.append("Failed to strip \(strip.failed) file(s) from tarball frontend.")
            }
        } else {
            warnings.append("Frontend dist not found; tarball Resources/ is empty.")
        }

        // .desktop (Exec 는 같은 디렉터리의 binary 를 가정 — 단순 배포용)
        let desktopName = slugify(opts.appName)
        try renderLinuxDesktopFile(
            appName: opts.appName,
            execCommand: "./\(exeName)",
            iconName: opts.iconPath != nil ? desktopName : nil,
            identifier: opts.identifier
        ).write(
            to: stage.appendingPathComponent("\(desktopName).desktop"),
            atomically: true, encoding: .utf8)

        // 아이콘
        if let icon = opts.iconPath, fm.fileExists(atPath: icon.path) {
            try safeCopy(from: icon, to: stage.appendingPathComponent("\(desktopName).png"), fm: fm)
        }

        try renderTarballInstallReadme(opts: opts, exeName: exeName).write(
            to: stage.appendingPathComponent("INSTALL.md"),
            atomically: true, encoding: .utf8)
    }

    /// Debian 패키지 트리. FHS 레이아웃 + DEBIAN/control 에서 시스템 라이브러리
    /// 의존성을 선언한다 (별도 번들링 없음 — Kalsae 철학).
    ///
    /// ```
    /// <root>/
    ///   DEBIAN/control
    ///   usr/bin/<id>                     # launcher 스크립트
    ///   usr/lib/<id>/<exe>               # 실제 ELF
    ///   usr/lib/<id>/Resources/...       # frontend dist
    ///   usr/lib/<id>/kalsae.json
    ///   usr/share/applications/<id>.desktop
    ///   usr/share/icons/hicolor/512x512/apps/<id>.png   (옵션)
    /// ```
    internal static func emitDebTree(
        root: URL,
        opts: LinuxOptions,
        exeName: String,
        fm: FileManager,
        warnings: inout [String]
    ) throws {
        let debian = root.appendingPathComponent("DEBIAN")
        let usrBin = root.appendingPathComponent("usr/bin")
        let libDir = root.appendingPathComponent("usr/lib").appendingPathComponent(opts.identifier)
        let appsDir = root.appendingPathComponent("usr/share/applications")
        let iconDir = root.appendingPathComponent("usr/share/icons/hicolor/512x512/apps")
        for d in [debian, usrBin, libDir, appsDir, iconDir] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }

        // 실제 ELF + 자원은 usr/lib/<id>/ 아래.
        let dstExe = libDir.appendingPathComponent(exeName)
        try safeCopy(from: opts.executablePath, to: dstExe, fm: fm)
        markExecutableIfPossible(dstExe, fm: fm)

        let dstConfig = libDir.appendingPathComponent("kalsae.json")
        try safeCopy(from: opts.configPath, to: dstConfig, fm: fm)
        try rewritePackagedConfig(at: dstConfig, frontendDist: "Resources", disableDevtools: true)

        let resources = libDir.appendingPathComponent("Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        if let dist = opts.frontendDist, fm.fileExists(atPath: dist.path) {
            try copyLinuxDistContents(of: dist, into: resources, fm: fm)
            let strip = KSBundleAnalyzer.strip(
                distURL: resources,
                stripSourceMaps: opts.stripSourceMaps,
                stripExtensions: opts.stripExtensions)
            if strip.failed > 0 {
                warnings.append("Failed to strip \(strip.failed) file(s) from .deb frontend.")
            }
        } else {
            warnings.append("Frontend dist not found; .deb usr/lib/\(opts.identifier)/Resources/ is empty.")
        }

        // usr/bin/<id> — cd 해서 ELF 를 실행하는 짧은 launcher.
        let launcher = """
            #!/bin/sh
            cd "/usr/lib/\(opts.identifier)" && exec "./\(exeName)" "$@"
            """
        let launcherURL = usrBin.appendingPathComponent(opts.identifier)
        try launcher.write(to: launcherURL, atomically: true, encoding: .utf8)
        markExecutableIfPossible(launcherURL, fm: fm)

        // .desktop — Exec 는 PATH 상의 launcher 사용.
        try renderLinuxDesktopFile(
            appName: opts.appName,
            execCommand: opts.identifier,
            iconName: opts.identifier,
            identifier: opts.identifier
        ).write(
            to: appsDir.appendingPathComponent("\(opts.identifier).desktop"),
            atomically: true, encoding: .utf8)

        // 아이콘 (옵션). 512x512 PNG 가정.
        if let icon = opts.iconPath, fm.fileExists(atPath: icon.path) {
            try safeCopy(from: icon, to: iconDir.appendingPathComponent("\(opts.identifier).png"), fm: fm)
        } else {
            warnings.append("No icon provided for .deb; defaulting to no icon entry.")
        }

        // DEBIAN/control — 시스템 GTK4 + WebKitGTK 6.0 + libsoup 3 를 Depends 로 선언.
        let installedSize = approximateInstalledSizeKB(at: root, fm: fm)
        try renderDebControl(opts: opts, installedSizeKB: installedSize).write(
            to: debian.appendingPathComponent("control"),
            atomically: true, encoding: .utf8)
    }

    /// AppImage AppDir 트리. `appimagetool` 입력으로 사용.
    ///
    /// ```
    /// <AppDir>/
    ///   AppRun                                 # 셸 launcher
    ///   <id>.desktop                           # 루트 필수
    ///   <id>.png                               # 루트 필수 (.DirIcon 대체)
    ///   usr/bin/<exe>
    ///   usr/share/Resources/...                # frontend dist
    ///   usr/share/kalsae.json
    ///   usr/share/applications/<id>.desktop    # XDG 호환용 사본
    ///   usr/share/icons/hicolor/512x512/apps/<id>.png
    /// ```
    internal static func emitAppImageTree(
        appDir: URL,
        opts: LinuxOptions,
        exeName: String,
        fm: FileManager,
        warnings: inout [String]
    ) throws {
        let usrBin = appDir.appendingPathComponent("usr/bin")
        let shareDir = appDir.appendingPathComponent("usr/share")
        let appsDir = appDir.appendingPathComponent("usr/share/applications")
        let iconDir = appDir.appendingPathComponent("usr/share/icons/hicolor/512x512/apps")
        for d in [usrBin, shareDir, appsDir, iconDir] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }

        // exe
        let dstExe = usrBin.appendingPathComponent(exeName)
        try safeCopy(from: opts.executablePath, to: dstExe, fm: fm)
        markExecutableIfPossible(dstExe, fm: fm)

        // config + frontend (usr/share/ 아래; AppRun 이 cd 해서 실행)
        let dstConfig = shareDir.appendingPathComponent("kalsae.json")
        try safeCopy(from: opts.configPath, to: dstConfig, fm: fm)
        try rewritePackagedConfig(at: dstConfig, frontendDist: "Resources", disableDevtools: true)

        let resources = shareDir.appendingPathComponent("Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        if let dist = opts.frontendDist, fm.fileExists(atPath: dist.path) {
            try copyLinuxDistContents(of: dist, into: resources, fm: fm)
            let strip = KSBundleAnalyzer.strip(
                distURL: resources,
                stripSourceMaps: opts.stripSourceMaps,
                stripExtensions: opts.stripExtensions)
            if strip.failed > 0 {
                warnings.append("Failed to strip \(strip.failed) file(s) from AppImage frontend.")
            }
        } else {
            warnings.append("Frontend dist not found; AppImage usr/share/Resources/ is empty.")
        }

        // AppRun
        let appRunURL = appDir.appendingPathComponent("AppRun")
        try renderAppImageAppRun(exeName: exeName).write(
            to: appRunURL, atomically: true, encoding: .utf8)
        markExecutableIfPossible(appRunURL, fm: fm)

        // 루트 + share 양쪽에 .desktop
        let desktop = renderLinuxDesktopFile(
            appName: opts.appName,
            execCommand: exeName,
            iconName: opts.identifier,
            identifier: opts.identifier)
        try desktop.write(
            to: appDir.appendingPathComponent("\(opts.identifier).desktop"),
            atomically: true, encoding: .utf8)
        try desktop.write(
            to: appsDir.appendingPathComponent("\(opts.identifier).desktop"),
            atomically: true, encoding: .utf8)

        // 아이콘 (루트 + share 양쪽)
        if let icon = opts.iconPath, fm.fileExists(atPath: icon.path) {
            try safeCopy(from: icon, to: appDir.appendingPathComponent("\(opts.identifier).png"), fm: fm)
            try safeCopy(from: icon, to: iconDir.appendingPathComponent("\(opts.identifier).png"), fm: fm)
        } else {
            warnings.append("AppImage requires an icon at the AppDir root; using empty placeholder may cause appimagetool to fail.")
        }
    }

    // MARK: - 렌더러 (순수 함수 — 테스트 친화적)

    /// XDG `.desktop` 파일. https://specifications.freedesktop.org/desktop-entry-spec/
    public static func renderLinuxDesktopFile(
        appName: String,
        execCommand: String,
        iconName: String?,
        identifier: String
    ) -> String {
        var lines = [
            "[Desktop Entry]",
            "Type=Application",
            "Version=1.0",
            "Name=\(escapeDesktopValue(appName))",
            "Exec=\(escapeDesktopValue(execCommand))",
            "Terminal=false",
            "Categories=Utility;",
            "StartupWMClass=\(escapeDesktopValue(identifier))",
        ]
        if let iconName {
            lines.append("Icon=\(escapeDesktopValue(iconName))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Debian `DEBIAN/control` 파일. `Depends:` 가 시스템 GTK4 / WebKitGTK 6.0 /
    /// libsoup 3 를 선언 — 별도 번들링이 없음을 형식적으로 증명한다.
    public static func renderDebControl(opts: LinuxOptions, installedSizeKB: Int) -> String {
        let maintainer = opts.maintainer ?? "Unknown <unknown@example.com>"
        let description = "\(opts.appName) — packaged with Kalsae."
        // GTK4 + WebKitGTK 6.0 + libsoup 3 의 Ubuntu 24.04 (noble) 표준 패키지 이름.
        // Debian 13 (trixie) 도 동일. 22.04 (jammy) 는 webkit2gtk-4.1 / libsoup2.4 이므로
        // 본 패키지는 24.04+ / Debian 13+ 를 타깃으로 한다.
        let depends = "libgtk-4-1 (>= 4.10), libwebkitgtk-6.0-4 | libwebkitgtk-6.0-4t64, libsoup-3.0-0"
        return """
            Package: \(opts.identifier)
            Version: \(opts.version)
            Section: web
            Priority: optional
            Architecture: \(opts.architecture.debArchitecture)
            Maintainer: \(maintainer)
            Installed-Size: \(installedSizeKB)
            Depends: \(depends)
            Description: \(description)

            """ + "\n"
    }

    /// AppImage AppRun. `$APPDIR` 는 appimagetool 가 런타임에 주입한다.
    public static func renderAppImageAppRun(exeName: String) -> String {
        """
        #!/bin/sh
        HERE="$(dirname "$(readlink -f "${0}")")"
        export PATH="${HERE}/usr/bin:${PATH}"
        cd "${HERE}/usr/share" && exec "${HERE}/usr/bin/\(exeName)" "$@"
        """
    }

    static func renderTarballInstallReadme(opts: LinuxOptions, exeName: String) -> String {
        """
        # \(opts.appName) \(opts.version) — Linux \(opts.architecture.rawValue)

        ## Install (system-wide)

        ```sh
        sudo cp -r . /opt/\(slugify(opts.appName))
        sudo ln -sf /opt/\(slugify(opts.appName))/\(exeName) /usr/local/bin/\(slugify(opts.appName))
        sudo cp \(slugify(opts.appName)).desktop /usr/share/applications/
        ```

        ## Runtime dependencies

        - GTK 4 (libgtk-4-1)
        - WebKitGTK 6.0 (libwebkitgtk-6.0-4 or libwebkitgtk-6.0-4t64)
        - libsoup 3 (libsoup-3.0-0)

        Install on Ubuntu 24.04+ / Debian 13+:

        ```sh
        sudo apt install libgtk-4-1 libwebkitgtk-6.0-4t64 libsoup-3.0-0
        ```
        """
    }

    static func renderLinuxReadme(opts: LinuxOptions, nextSteps: [String]) -> String {
        let header = """
            # \(opts.appName) \(opts.version) — Linux packaging output

            Packaged with [Kalsae](https://github.com/) — single-source, secure, OS-engine-reusing
            desktop apps. This directory contains the **emit-only** tree for the formats you
            requested. The final artifacts (`.tar.gz`, `.deb`, `.AppImage`) are produced by
            standard Linux tooling — Kalsae does not bundle Chromium or Node.

            ## Next steps (run on a Linux host)

            """
        let steps = nextSteps.map { "```sh\n\($0)\n```" }.joined(separator: "\n\n")
        return header + "\n" + steps + "\n"
    }

    // MARK: - 검증 helper

    /// 역도메인 (Apple/Android 와 동일 — 소문자 강제).
    static func isValidLinuxIdentifier(_ id: String) -> Bool {
        let segs = id.split(separator: ".", omittingEmptySubsequences: false)
        guard segs.count >= 2 else { return false }
        for seg in segs {
            guard let first = seg.first else { return false }
            guard first.isLetter, first.isLowercase else { return false }
            for ch in seg {
                if ch.isLetter && ch.isLowercase { continue }
                if ch.isNumber { continue }
                if ch == "_" || ch == "-" { continue }
                return false
            }
        }
        return true
    }

    /// Debian 정책 §5.6.12 의 단순화 — 숫자 시작, 영숫자/`.+-~` 허용.
    static func isValidDebVersion(_ v: String) -> Bool {
        guard let first = v.first, first.isNumber else { return false }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.+-~:")
        return v.allSatisfy { allowed.contains($0) }
    }

    /// `.desktop` value escaping (스펙 §5: `\`, `\n`, `\t`, `\r` 만 escape).
    static func escapeDesktopValue(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// CFBundleExecutable 처리와 동일 — 공백/특수문자 → `_`.
    static func sanitizedLinuxExecutableName(_ appName: String) -> String {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let mapped = appName.map { allowed.contains($0) ? $0 : "_" }
        let result = String(mapped)
        return result.isEmpty ? "app" : result
    }

    /// `.desktop` 파일 이름 / 디렉터리 슬러그 — 소문자 + 하이픈.
    static func slugify(_ s: String) -> String {
        let lower = s.lowercased()
        let mapped = lower.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            if ch == "-" || ch == "_" { return ch }
            return "-"
        }
        // 연속 하이픈 / 양끝 하이픈 정리
        var out = String(mapped)
        while out.contains("--") {
            out = out.replacingOccurrences(of: "--", with: "-")
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return out.isEmpty ? "app" : out
    }

    /// `safeCopy` 와 동일한 파일을 사용하지만 PackagerAndroid 의 `copyDistContents`
    /// 를 참고해 디렉터리 내용물만 복사한다 (디렉터리 자체는 제외).
    static func copyLinuxDistContents(of src: URL, into dst: URL, fm: FileManager) throws {
        let entries = try fm.contentsOfDirectory(atPath: src.path)
        for name in entries {
            let s = src.appendingPathComponent(name)
            let d = dst.appendingPathComponent(name)
            if fm.fileExists(atPath: d.path) {
                try retryingTransient { try fm.removeItem(at: d) }
            }
            try retryingTransient { try fm.copyItem(at: s, to: d) }
        }
    }

    /// POSIX 호스트(Linux/macOS) 에서만 실행 비트를 보존. Windows 호스트에서는
    /// no-op (dpkg-deb 가 Linux 에서 실행되며 자체적으로 모드 정규화).
    static func markExecutableIfPossible(_ url: URL, fm: FileManager) {
        #if os(macOS) || os(Linux)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        #endif
    }

    /// 트리 전체 바이트 합 → KB (DEBIAN/control `Installed-Size:`).
    static func approximateInstalledSizeKB(at root: URL, fm: FileManager) -> Int {
        guard let it = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in it {
            let vals = try? url.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(vals?.fileSize ?? 0)
        }
        return max(1, Int(total / 1024))
    }
}
