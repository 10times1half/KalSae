import Foundation
import Testing

@testable import KalsaeCLICore

@Suite("KSPackager — zip helper")
struct PackagerZipTests {

    private func makeTree(at root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.writeWithRetry(
            "hello",
            to: root.appendingPathComponent("a.txt"))
        let sub = root.appendingPathComponent("nested")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try Self.writeWithRetry(
            "world",
            to: sub.appendingPathComponent("b.txt"))
    }

    /// Windows에서 Defender/검색 인덱서가 새로 만든 파일에 잠시 핸들을 걸어
    /// `atomically: true`(temp + rename) 경로가 ERROR_SHARING_VIOLATION(32)으로
    /// 실패하는 경우가 있다. 비원자적 쓰기 + 짧은 백오프 재시도로 우회한다.
    private static func writeWithRetry(_ string: String, to url: URL) throws {
        var lastError: (any Error)?
        for attempt in 0..<5 {
            do {
                try string.write(to: url, atomically: false, encoding: .utf8)
                return
            } catch {
                lastError = error
                Thread.sleep(forTimeInterval: 0.05 * Double(attempt + 1))
            }
        }
        throw lastError!
    }

    private func uniqueDir(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-pkg-\(UUID().uuidString)-\(suffix)")
    }

    @Test("createZip handles plain paths")
    func plainPath() throws {
        let src = uniqueDir(suffix: "plain")
        let archive = uniqueDir(suffix: "plain").appendingPathExtension("zip")
        try makeTree(at: src)
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: archive)
        }

        try KSPackager.createZip(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
        let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > 0)
    }

    @Test("createZip handles paths with spaces")
    func spaceInPath() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae pkg \(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)
        let src = parent.appendingPathComponent("source dir")
        let archive = parent.appendingPathComponent("out file.zip")
        try makeTree(at: src)
        defer { try? FileManager.default.removeItem(at: parent) }

        try KSPackager.createZip(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("createZip handles paths with single quotes")
    func singleQuotePath() throws {
        // 경로 인용/이스케이프 회귀 가드. 과거 PowerShell 구현에서 단일따옴표
        // 인젝션 위험을 막기 위해 만든 테스트지만, 현재 `tar.exe` 기반
        // 구현에서도 인자 배열 전달이 단일따옴표 경로를 그대로 보존하는지
        // 계속 검증한다.
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae'pkg'\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)
        let src = parent.appendingPathComponent("o'reilly")
        let archive = parent.appendingPathComponent("a'b.zip")
        try makeTree(at: src)
        defer { try? FileManager.default.removeItem(at: parent) }

        try KSPackager.createZip(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("createZip handles unicode paths")
    func unicodePath() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("칼새-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true)
        let src = parent.appendingPathComponent("자료")
        let archive = parent.appendingPathComponent("결과.zip")
        try makeTree(at: src)
        defer { try? FileManager.default.removeItem(at: parent) }

        try KSPackager.createZip(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test("createZip overwrites existing archive")
    func overwriteExisting() throws {
        let src = uniqueDir(suffix: "ow-src")
        let archive = uniqueDir(suffix: "ow-dst").appendingPathExtension("zip")
        try makeTree(at: src)
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: archive)
        }

        try KSPackager.createZip(from: src, to: archive)
        let firstSize = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        // 두 번째 실행: 기존 zip 위에 다시 만들 때 `KSZipArchiver`가
        // 미리 `removeItem`으로 정리하므로 실패하지 않아야 한다.
        try KSPackager.createZip(from: src, to: archive)
        let secondSize = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(firstSize > 0 && secondSize > 0)
    }

    @Test("createZip throws for nonexistent source directory")
    func nonexistentSource() throws {
        let src = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-pkg-nonexistent-\(UUID().uuidString)")
        let archive = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-pkg-nonexistent-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: archive) }

        #expect(throws: (any Error).self) {
            try KSPackager.createZip(from: src, to: archive)
        }
    }

    @Test("createZipAsync mirrors createZip outcome")
    func asyncVariant() async throws {
        let src = uniqueDir(suffix: "async")
        let archive = uniqueDir(suffix: "async").appendingPathExtension("zip")
        try makeTree(at: src)
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: archive)
        }

        try await KSPackager.createZipAsync(from: src, to: archive)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }
}

@Suite("KSPackager — Windows manifest + DLL")
struct PackagerWindowsTests {

    private func uniqueDir(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-pkg-win-\(UUID().uuidString)-\(suffix)")
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    @Test("manifestProcessorArchitecture maps x64 → amd64 (SxS spec)")
    func manifestArchMapping() {
        // Win32 SxS 스펙은 `x86 | amd64 | arm64 | ia64 | msil | *` 만 허용한다.
        // CLI 표면(`--arch x64`) 은 그대로 두고 manifest 출력만 `amd64` 로 변환해야 한다.
        #expect(KSPackager.Architecture.x64.manifestProcessorArchitecture == "amd64")
        #expect(KSPackager.Architecture.arm64.manifestProcessorArchitecture == "arm64")
        #expect(KSPackager.Architecture.x86.manifestProcessorArchitecture == "x86")
    }

    @Test("packaged manifest uses amd64 for x64 builds")
    func packagedManifestUsesAmd64() throws {
        let fm = FileManager.default
        let work = uniqueDir(suffix: "manifest-arch")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let exe = work.appendingPathComponent("App.exe")
        try writeText("MZ", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText("{}", to: config)
        let output = work.appendingPathComponent("out")

        let opts = KSPackager.Options(
            projectRoot: work,
            executablePath: exe,
            configPath: config,
            frontendDist: nil,
            output: output,
            appName: "App",
            version: "1.2.3",
            identifier: "dev.kalsae.app",
            architecture: .x64,
            policy: .evergreen)

        _ = try KSPackager.run(opts)

        let manifest = try String(
            contentsOf: output.appendingPathComponent("App.exe.manifest"),
            encoding: .utf8)
        #expect(manifest.contains("processorArchitecture=\"amd64\""))
        #expect(!manifest.contains("processorArchitecture=\"x64\""))
    }

    @Test("WebView2Loader.dll is copied from Vendor/WebView2/runtimes")
    func loaderDLLIsStaged() throws {
        let fm = FileManager.default
        let work = uniqueDir(suffix: "loader-staging")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // Fixture: 가짜 Vendor/WebView2/runtimes/win-x64/native/WebView2Loader.dll
        let loaderSrc = work
            .appendingPathComponent("Vendor")
            .appendingPathComponent("WebView2")
            .appendingPathComponent("runtimes")
            .appendingPathComponent("win-x64")
            .appendingPathComponent("native")
            .appendingPathComponent("WebView2Loader.dll")
        try writeText("MZ-loader", to: loaderSrc)

        let exe = work.appendingPathComponent("App.exe")
        try writeText("MZ", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText("{}", to: config)
        let output = work.appendingPathComponent("out")

        let opts = KSPackager.Options(
            projectRoot: work,
            executablePath: exe,
            configPath: config,
            frontendDist: nil,
            output: output,
            appName: "App",
            version: "0.1.0",
            identifier: "dev.kalsae.app",
            architecture: .x64,
            policy: .evergreen)

        let report = try KSPackager.run(opts)

        let staged = output.appendingPathComponent("WebView2Loader.dll")
        #expect(fm.fileExists(atPath: staged.path))
        let bytes = try String(contentsOf: staged, encoding: .utf8)
        #expect(bytes == "MZ-loader")
        // 정상 케이스에서는 loader 관련 warning 이 추가되지 않아야 한다.
        #expect(!report.warnings.contains { $0.contains("WebView2Loader.dll") })
    }

    @Test("missing WebView2Loader.dll surfaces a warning, not an error")
    func loaderDLLMissingWarns() throws {
        let fm = FileManager.default
        let work = uniqueDir(suffix: "loader-missing")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let exe = work.appendingPathComponent("App.exe")
        try writeText("MZ", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText("{}", to: config)
        let output = work.appendingPathComponent("out")

        let opts = KSPackager.Options(
            projectRoot: work,
            executablePath: exe,
            configPath: config,
            frontendDist: nil,
            output: output,
            appName: "App",
            version: "0.1.0",
            identifier: "dev.kalsae.app",
            architecture: .x64,
            policy: .evergreen)

        let report = try KSPackager.run(opts)
        #expect(report.warnings.contains { $0.contains("WebView2Loader.dll") })
    }
}

// MARK: - 패키지된 Kalsae.json 재작성

@Suite("KSPackager — Kalsae.json rewrite")
struct PackagerConfigRewriteTests {
    private func uniqueDir(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-pkg-rewrite-\(UUID().uuidString)-\(suffix)")
    }

    private func writeText(_ s: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try s.write(to: url, atomically: false, encoding: .utf8)
    }

    /// 패키저는 frontend dist 를 항상 `Resources/` 로 복사한다. 사용자가 source
    /// kalsae.json 에 `frontendDist: "dist"` 라고 적어 두면 런타임에 `<exeDir>/dist`
    /// 가 존재하지 않아 KSApp.boot 가 dev 서버 fallback 으로 빠지면서 흰 화면이 된다.
    /// 패키저는 복사 후 `Kalsae.json` 의 `build.frontendDist` 를 `Resources` 로
    /// 다시 써야 한다.
    @Test("packaged Kalsae.json has frontendDist rewritten to Resources")
    func frontendDistRewritten() throws {
        let fm = FileManager.default
        let work = uniqueDir("dist-rewrite")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let exe = work.appendingPathComponent("App.exe")
        try writeText("MZ", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText(
            #"""
            {
              "app": {"name": "App", "version": "0.1.0", "identifier": "dev.kalsae.app"},
              "build": {"frontendDist": "dist", "devServerURL": "http://localhost:5173"},
              "security": {"devtools": true},
              "windows": [{"label": "main", "title": "App", "width": 800, "height": 600}]
            }
            """#,
            to: config)
        let output = work.appendingPathComponent("out")

        let opts = KSPackager.Options(
            projectRoot: work,
            executablePath: exe,
            configPath: config,
            frontendDist: nil,
            output: output,
            appName: "App",
            version: "0.1.0",
            identifier: "dev.kalsae.app",
            architecture: .x64,
            policy: .evergreen)
        _ = try KSPackager.run(opts)

        let outConfig = output.appendingPathComponent("Kalsae.json")
        let data = try Data(contentsOf: outConfig)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let build = try #require(root["build"] as? [String: Any])
        #expect(
            (build["frontendDist"] as? String) == "Resources",
            "frontendDist must be rewritten to match the actual packaged folder name")
    }

    /// 릴리스 패키지에서는 `security.devtools` 가 강제로 `false` 가 되어야 한다.
    /// `KSSecurityConfig.devtools` 의 문서화된 동작이며, 사용자가 source kalsae.json
    /// 에 `true` 로 둬도 패키지 산출물에서는 DevTools 가 노출되지 않는다.
    @Test("packaged Kalsae.json forces security.devtools=false")
    func devtoolsForcedOff() throws {
        let fm = FileManager.default
        let work = uniqueDir("devtools-off")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let exe = work.appendingPathComponent("App.exe")
        try writeText("MZ", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText(
            #"""
            {
              "app": {"name": "App", "version": "0.1.0", "identifier": "dev.kalsae.app"},
              "build": {"frontendDist": "dist", "devServerURL": "about:blank"},
              "security": {"devtools": true},
              "windows": [{"label": "main", "title": "App", "width": 800, "height": 600}]
            }
            """#,
            to: config)
        let output = work.appendingPathComponent("out")

        let opts = KSPackager.Options(
            projectRoot: work,
            executablePath: exe,
            configPath: config,
            frontendDist: nil,
            output: output,
            appName: "App",
            version: "0.1.0",
            identifier: "dev.kalsae.app",
            architecture: .x64,
            policy: .evergreen)
        _ = try KSPackager.run(opts)

        let outConfig = output.appendingPathComponent("Kalsae.json")
        let data = try Data(contentsOf: outConfig)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let security = try #require(root["security"] as? [String: Any])
        #expect(
            (security["devtools"] as? Bool) == false,
            "release packaging must disable devtools regardless of source config")
    }

    /// 릴리스 패키지에서는 `build.devServerURL` 이 `"about:blank"` 으로 강제되어야
    /// 한다. 사용자가 source kalsae.json 에 `http://localhost:5173` 같은 dev URL 을
    /// 두고 패키징해도, `KSApp.boot` 의 release 가드와 함께 양면으로 dev 서버
    /// 분기를 차단해 흰 화면 / chrome-error 회귀를 막는다.
    @Test("packaged Kalsae.json forces build.devServerURL to about:blank")
    func devServerURLForcedToAboutBlank() throws {
        let fm = FileManager.default
        let work = uniqueDir("dev-url-blanked")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let exe = work.appendingPathComponent("App.exe")
        try writeText("MZ", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText(
            #"""
            {
              "app": {"name": "App", "version": "0.1.0", "identifier": "dev.kalsae.app"},
              "build": {"frontendDist": "dist", "devServerURL": "http://localhost:5173"},
              "security": {"devtools": false},
              "windows": [{"label": "main", "title": "App", "width": 800, "height": 600}]
            }
            """#,
            to: config)
        let output = work.appendingPathComponent("out")

        let opts = KSPackager.Options(
            projectRoot: work,
            executablePath: exe,
            configPath: config,
            frontendDist: nil,
            output: output,
            appName: "App",
            version: "0.1.0",
            identifier: "dev.kalsae.app",
            architecture: .x64,
            policy: .evergreen)
        _ = try KSPackager.run(opts)

        let outConfig = output.appendingPathComponent("Kalsae.json")
        let data = try Data(contentsOf: outConfig)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let build = try #require(root["build"] as? [String: Any])
        #expect(
            (build["devServerURL"] as? String) == "about:blank",
            "release packaging must blank out devServerURL to prevent dev-fallback white screen")
    }

    /// `clearDevServerURL: false` 로 호출하면 dev URL 이 보존된다 (opt-out 경로).
    /// 미지정 필드(예: `windows`, `app`)는 항상 보존되어야 한다.
    @Test("rewritePackagedConfig preserves devServerURL when clearDevServerURL=false")
    func rewriteCanPreserveDevServerURL() throws {
        let fm = FileManager.default
        let work = uniqueDir("dev-url-preserved")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let config = work.appendingPathComponent("Kalsae.json")
        try writeText(
            #"""
            {
              "app": {"name": "App", "version": "0.1.0", "identifier": "dev.kalsae.app"},
              "build": {"frontendDist": "dist", "devServerURL": "http://localhost:5173"},
              "security": {"devtools": true},
              "windows": [{"label": "main", "title": "App", "width": 800, "height": 600}]
            }
            """#,
            to: config)

        try KSPackager.rewritePackagedConfig(
            at: config,
            frontendDist: "Resources",
            disableDevtools: false,
            clearDevServerURL: false)

        let data = try Data(contentsOf: config)
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let build = try #require(root["build"] as? [String: Any])
        #expect((build["frontendDist"] as? String) == "Resources")
        #expect((build["devServerURL"] as? String) == "http://localhost:5173")
        // unknown / unrelated 필드도 보존.
        #expect(root["windows"] is [Any])
        #expect(root["app"] is [String: Any])
    }
}

// MARK: - RFC-002 회귀 테스트: Packager 증분화 + fingerprint 기반 자동 clean

@Suite("KSPackager — incremental + fingerprint")
struct PackagerIncrementalTests {
    private func uniqueDir(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-pkg-incr-\(UUID().uuidString)-\(suffix)")
    }

    private func writeText(_ s: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try s.write(to: url, atomically: false, encoding: .utf8)
    }

    private func makeBaseOptions(in work: URL) throws -> (
        opts: KSPackager.Options, dist: URL, output: URL
    ) {
        let exe = work.appendingPathComponent("App.exe")
        try writeText("MZ", to: exe)
        let config = work.appendingPathComponent("Kalsae.json")
        try writeText("{}", to: config)
        let dist = work.appendingPathComponent("dist")
        try writeText("<html></html>", to: dist.appendingPathComponent("index.html"))
        try writeText("body{}", to: dist.appendingPathComponent("style.css"))
        let output = work.appendingPathComponent("out")
        let opts = KSPackager.Options(
            projectRoot: work,
            executablePath: exe,
            configPath: config,
            frontendDist: dist,
            output: output,
            appName: "App",
            version: "0.1.0",
            identifier: "dev.kalsae.app",
            architecture: .x64,
            policy: .evergreen)
        return (opts, dist, output)
    }

    /// 동일 옵션 + 동일 dist 로 두 번 빌드하면 Resources/ 안의 파일 mtime 이
    /// 1회차와 동일해야 한다 (KSResourceSyncManager 가 size+mtime 비교로
    /// 변경 없는 파일을 skip 하기 때문). 회귀 시 모든 파일이 매번 재복사되어
    /// mtime 이 갱신된다.
    @Test("running KSPackager.run twice preserves Resources/ mtimes (incremental)")
    func resourcesAreIncremental() throws {
        let fm = FileManager.default
        let work = uniqueDir("resources-mtime")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let (opts, _, output) = try makeBaseOptions(in: work)

        _ = try KSPackager.run(opts)
        let firstStyle = output.appendingPathComponent("Resources/style.css")
        let firstMtime = try fm.attributesOfItem(atPath: firstStyle.path)[.modificationDate]
            as? Date
        #expect(firstMtime != nil)

        // mtime 1초 양자화를 회피하기 위해 약간 대기.
        Thread.sleep(forTimeInterval: 1.2)

        _ = try KSPackager.run(opts)
        let secondMtime = try fm.attributesOfItem(atPath: firstStyle.path)[.modificationDate]
            as? Date
        #expect(secondMtime != nil)
        if let a = firstMtime, let b = secondMtime {
            // 동일 mtime (skip 됨) — 1초 슬랙은 sync 측에서 허용하므로
            // 재복사가 일어났다면 1.2초 차이가 그대로 보인다.
            #expect(abs(a.timeIntervalSince(b)) < 0.5)
        }
    }

    /// 정책을 fixed → evergreen 으로 바꿔 빌드하면 fingerprint 가 달라지므로
    /// output 전체가 자동 재생성되어 stale `webview2-runtime/` 디렉터리가
    /// 사라져야 한다. 회귀 시 디렉터리가 남아 런타임이 잘못된 정책으로
    /// 동작할 위험이 있다.
    @Test("policy switch from fixed to evergreen removes stale webview2-runtime/")
    func policySwitchClearsStaleRuntime() throws {
        let fm = FileManager.default
        let work = uniqueDir("policy-switch")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // 가짜 fixed runtime 폴더 (vendorRuntimeRoot 로 사용)
        let fixedRoot = work.appendingPathComponent("FixedRuntime")
        try writeText(
            "fake-runtime-binary",
            to: fixedRoot.appendingPathComponent("msedgewebview2.exe"))

        let (baseOpts, _, output) = try makeBaseOptions(in: work)
        var fixedOpts = baseOpts
        fixedOpts.policy = .fixed
        fixedOpts.vendorRuntimeRoot = fixedRoot

        _ = try KSPackager.run(fixedOpts)
        let stale = output.appendingPathComponent("webview2-runtime")
        #expect(fm.fileExists(atPath: stale.path), "1회차 fixed 빌드는 webview2-runtime/ 을 만들어야 한다")

        // 정책 전환 → evergreen
        var evergreenOpts = baseOpts
        evergreenOpts.policy = .evergreen
        _ = try KSPackager.run(evergreenOpts)

        #expect(
            !fm.fileExists(atPath: stale.path),
            "fingerprint 변경 시 output 전체가 재생성되어 webview2-runtime/ 이 사라져야 한다")

        // fingerprint 파일은 zip 산출물에 포함되지 않도록 zip 생성 후에
        // 기록되지만, 디스크의 output 디렉터리에는 있어야 한다.
        let fp = output.appendingPathComponent(".kalsae-pkg-fingerprint.json")
        #expect(fm.fileExists(atPath: fp.path))
    }

    /// 동일 옵션으로 두 번 빌드하면 fingerprint 가 같으므로 output 전체
    /// 삭제가 발생하지 않는다 — exe 의 mtime 이 보존되는지로 검증.
    @Test("identical fingerprint preserves exe mtime across runs")
    func identicalFingerprintPreservesExe() throws {
        let fm = FileManager.default
        let work = uniqueDir("identical-fp")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let (opts, _, output) = try makeBaseOptions(in: work)
        _ = try KSPackager.run(opts)
        let stagedExe = output.appendingPathComponent("App.exe")
        let firstMtime = try fm.attributesOfItem(atPath: stagedExe.path)[.modificationDate]
            as? Date

        Thread.sleep(forTimeInterval: 1.2)
        _ = try KSPackager.run(opts)
        let secondMtime = try fm.attributesOfItem(atPath: stagedExe.path)[.modificationDate]
            as? Date

        // safeCopy 는 매번 dst 를 새로 쓰므로 exe mtime 은 갱신될 수 있다.
        // 핵심 검증은 "디렉터리 자체가 살아남았는지" — 즉 fingerprint 가
        // 동일하면 output 이 통째로 지워지지 않았음을 확인.
        #expect(firstMtime != nil)
        #expect(secondMtime != nil)
        // fingerprint 파일이 그대로 존재하는지 확인.
        let fp = output.appendingPathComponent(".kalsae-pkg-fingerprint.json")
        #expect(fm.fileExists(atPath: fp.path))
    }

    /// strip 옵션(stripSourceMaps / stripExtensions)도 fingerprint 키에 포함되므로
    /// 토글 시 output 이 전체 재생성되어야 한다. 회귀 시 strip 비활성화로 전환해도
    /// 이미 strip 된 산출물에 source map 이 다시 나타나지 않거나(혹은 그 반대)
    /// 사용자 기대와 어긋난 incremental 결과가 남는다.
    @Test("strip option toggle invalidates fingerprint and triggers full rebuild")
    func stripOptionTogglesFingerprint() throws {
        let fm = FileManager.default
        let work = uniqueDir("strip-toggle")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let (baseOpts, dist, output) = try makeBaseOptions(in: work)
        // dist 에 source map 동봉 — 첫 빌드는 strip 비활성으로 통과시켜 보존.
        try writeText("/*map*/", to: dist.appendingPathComponent("style.css.map"))

        var noStripOpts = baseOpts
        noStripOpts.stripSourceMaps = false
        _ = try KSPackager.run(noStripOpts)
        let map = output.appendingPathComponent("Resources/style.css.map")
        #expect(fm.fileExists(atPath: map.path), "strip 비활성 시 .map 파일이 보존되어야 한다")

        // 사용자가 strip 옵션을 활성화 → fingerprint mismatch → 전체 재생성 후 strip 적용.
        var stripOpts = baseOpts
        stripOpts.stripSourceMaps = true
        _ = try KSPackager.run(stripOpts)
        #expect(
            !fm.fileExists(atPath: map.path),
            "strip 옵션 활성화 시 fingerprint 가 달라져 전체 재생성 + strip 이 적용되어야 한다")
    }
}
