import Foundation
import Testing

@testable import KalsaeCLICore
@testable import KalsaeCore

@Suite("KSPackager — Android Gradle project (RFC-007)")
struct PackagerAndroidTests {

    private func uniqueDir(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-android-\(UUID().uuidString)-\(suffix)")
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try text.write(to: url, atomically: false, encoding: .utf8)
    }

    /// 가짜 .so + 가짜 Kalsae.json + 빈 dist 가 모인 작업 디렉터리를 만든다.
    private func makeFixture(suffix: String) throws -> (work: URL, opts: KSPackager.AndroidOptions) {
        let fm = FileManager.default
        let work = uniqueDir(suffix: suffix)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let lib = work.appendingPathComponent("libKalsaePlatformAndroid.so")
        try writeText("ELF-fake", to: lib)

        let config = work.appendingPathComponent("Kalsae.json")
        try writeText(
            #"{"app":{"name":"Demo"},"build":{"frontendDist":"dist"},"security":{"devtools":true}}"#,
            to: config)

        let dist = work.appendingPathComponent("dist")
        try fm.createDirectory(at: dist, withIntermediateDirectories: true)
        try writeText("<!doctype html><title>x</title>", to: dist.appendingPathComponent("index.html"))

        let output = work.appendingPathComponent("out")

        let opts = KSPackager.AndroidOptions(
            nativeLibPath: lib,
            configPath: config,
            frontendDist: dist,
            output: output,
            appName: "Demo App",
            version: "1.2.3",
            identifier: "com.example.demo",
            versionCode: 7,
            minimumAPILevel: 26,
            targetAPILevel: 35,
            architecture: .arm64,
            iconPath: nil,
            deepLinkSchemes: ["myapp"])
        return (work, opts)
    }

    // MARK: - Happy path: full structure

    @Test("Android project has expected directory structure")
    func projectStructure() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "structure")
        defer { try? fm.removeItem(at: work) }

        let report = try KSPackager.runAndroid(opts)
        let root = URL(fileURLWithPath: report.outputPath)

        #expect(report.policy == "android-gradle")
        // 루트 파일
        #expect(fm.fileExists(atPath: root.appendingPathComponent("build.gradle.kts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("settings.gradle.kts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("gradle.properties").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("gradle/libs.versions.toml").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("README.md").path))
        // app/
        #expect(fm.fileExists(atPath: root.appendingPathComponent("app/build.gradle.kts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("app/proguard-rules.pro").path))
        #expect(
            fm.fileExists(atPath: root.appendingPathComponent("app/src/main/AndroidManifest.xml").path))
        // Kotlin (com/example/demo)
        let kotlinDir = root.appendingPathComponent("app/src/main/kotlin/com/example/demo")
        #expect(fm.fileExists(atPath: kotlinDir.appendingPathComponent("MainActivity.kt").path))
        #expect(fm.fileExists(atPath: kotlinDir.appendingPathComponent("KalsaeJNI.kt").path))
        #expect(fm.fileExists(atPath: kotlinDir.appendingPathComponent("WebAppInterface.kt").path))
        // 리소스
        let res = root.appendingPathComponent("app/src/main/res")
        #expect(fm.fileExists(atPath: res.appendingPathComponent("values/strings.xml").path))
        #expect(fm.fileExists(atPath: res.appendingPathComponent("values/themes.xml").path))
        for density in ["mipmap-mdpi", "mipmap-hdpi", "mipmap-xhdpi", "mipmap-xxhdpi", "mipmap-xxxhdpi"] {
            #expect(
                fm.fileExists(
                    atPath: res.appendingPathComponent("\(density)/ic_launcher.png").path),
                "missing mipmap density: \(density)")
        }
        // assets + jniLibs
        let assets = root.appendingPathComponent("app/src/main/assets")
        #expect(fm.fileExists(atPath: assets.appendingPathComponent("Kalsae.json").path))
        #expect(fm.fileExists(atPath: assets.appendingPathComponent("index.html").path))
        #expect(
            fm.fileExists(
                atPath: root.appendingPathComponent(
                    "app/src/main/jniLibs/arm64-v8a/libKalsaePlatformAndroid.so"
                ).path))
    }

    // MARK: - Token substitution

    @Test("app/build.gradle.kts contains applicationId/versionCode/versionName/minSdk/targetSdk")
    func appGradleTokenSubstitution() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "tokens")
        defer { try? fm.removeItem(at: work) }

        let report = try KSPackager.runAndroid(opts)
        let root = URL(fileURLWithPath: report.outputPath)
        let appGradle = try String(
            contentsOf: root.appendingPathComponent("app/build.gradle.kts"), encoding: .utf8)

        #expect(appGradle.contains("applicationId = \"com.example.demo\""))
        #expect(appGradle.contains("versionCode = 7"))
        #expect(appGradle.contains("versionName = \"1.2.3\""))
        #expect(appGradle.contains("minSdk = 26"))
        #expect(appGradle.contains("targetSdk = 35"))
        #expect(appGradle.contains("\"arm64-v8a\""))
    }

    @Test("settings.gradle.kts contains rootProject.name")
    func settingsGradleHasRootName() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "settings")
        defer { try? fm.removeItem(at: work) }

        let report = try KSPackager.runAndroid(opts)
        let settings = try String(
            contentsOf: URL(fileURLWithPath: report.outputPath)
                .appendingPathComponent("settings.gradle.kts"),
            encoding: .utf8)
        #expect(settings.contains("rootProject.name = \"Demo App\""))
        #expect(settings.contains("include(\":app\")"))
    }

    // MARK: - Manifest

    @Test("AndroidManifest.xml contains LAUNCHER and deepLink intent-filter")
    func manifestIntents() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "manifest")
        defer { try? fm.removeItem(at: work) }

        let report = try KSPackager.runAndroid(opts)
        let xml = try String(
            contentsOf: URL(fileURLWithPath: report.outputPath)
                .appendingPathComponent("app/src/main/AndroidManifest.xml"),
            encoding: .utf8)

        #expect(xml.contains("android.intent.action.MAIN"))
        #expect(xml.contains("android.intent.category.LAUNCHER"))
        #expect(xml.contains("android.intent.action.VIEW"))
        #expect(xml.contains("android:scheme=\"myapp\""))
    }

    @Test("AndroidManifest.xml omits VIEW intent-filter when deepLinkSchemes is empty")
    func manifestNoDeepLink() throws {
        let fm = FileManager.default
        let (work, baseOpts) = try makeFixture(suffix: "manifest-none")
        defer { try? fm.removeItem(at: work) }

        var opts = baseOpts
        opts.deepLinkSchemes = []
        let report = try KSPackager.runAndroid(opts)
        let xml = try String(
            contentsOf: URL(fileURLWithPath: report.outputPath)
                .appendingPathComponent("app/src/main/AndroidManifest.xml"),
            encoding: .utf8)

        #expect(xml.contains("android.intent.action.MAIN"))
        #expect(!xml.contains("android.intent.action.VIEW"))
    }

    // MARK: - Kalsae.json rewrite

    @Test("Packaged Kalsae.json has frontendDist='.' and security.devtools=false")
    func configRewrite() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "rewrite")
        defer { try? fm.removeItem(at: work) }

        let report = try KSPackager.runAndroid(opts)
        let data = try Data(
            contentsOf: URL(fileURLWithPath: report.outputPath)
                .appendingPathComponent("app/src/main/assets/Kalsae.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let build = json?["build"] as? [String: Any]
        let security = json?["security"] as? [String: Any]
        #expect(build?["frontendDist"] as? String == ".")
        #expect(security?["devtools"] as? Bool == false)
    }

    // MARK: - Kotlin JNI emission

    @Test("KalsaeJNI.kt exposes register* hooks and onDialogResult bridge")
    func kotlinJNIEmissionContainsDialogBridge() throws {
        let fm = FileManager.default
        let (work, opts) = try makeFixture(suffix: "jni")
        defer { try? fm.removeItem(at: work) }

        let report = try KSPackager.runAndroid(opts)
        let kt = try String(
            contentsOf: URL(fileURLWithPath: report.outputPath)
                .appendingPathComponent("app/src/main/kotlin/com/example/demo/KalsaeJNI.kt"),
            encoding: .utf8)

        // 등록 진입점 5개 (RFC-007 Phase 4 scaffolding).
        #expect(kt.contains("registerShowAlert"))
        #expect(kt.contains("registerPickFile"))
        #expect(kt.contains("registerSaveFile"))
        #expect(kt.contains("registerSelectFolder"))
        #expect(kt.contains("registerShowContextMenu"))
        // request-id ↔ continuation 브리지.
        #expect(kt.contains("external fun onDialogResult(requestId: Int, resultJson: String)"))
    }

    // MARK: - Validation

    @Test("Missing native library produces a configInvalid error")
    func missingLibErrors() throws {
        let fm = FileManager.default
        let work = uniqueDir(suffix: "no-lib")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let config = work.appendingPathComponent("Kalsae.json")
        try writeText("{}", to: config)

        let opts = KSPackager.AndroidOptions(
            nativeLibPath: work.appendingPathComponent("does-not-exist.so"),
            configPath: config,
            frontendDist: nil,
            output: work.appendingPathComponent("out"),
            appName: "X",
            version: "1.0.0",
            identifier: "com.example.x")

        do {
            _ = try KSPackager.runAndroid(opts)
            Issue.record("Expected KSError(.configInvalid)")
        } catch let e as KSError {
            #expect(e.code == .configInvalid)
            #expect(e.message.contains("native library not found"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Invalid applicationId is rejected")
    func invalidIdentifier() throws {
        let fm = FileManager.default
        let (work, baseOpts) = try makeFixture(suffix: "bad-id")
        defer { try? fm.removeItem(at: work) }

        var opts = baseOpts
        opts.identifier = "BadId"  // 단일 세그먼트 + 대문자
        do {
            _ = try KSPackager.runAndroid(opts)
            Issue.record("Expected configInvalid")
        } catch let e as KSError {
            #expect(e.code == .configInvalid)
            #expect(e.message.contains("applicationId"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("minSdk below 26 is rejected")
    func minSdkTooLow() throws {
        let fm = FileManager.default
        let (work, baseOpts) = try makeFixture(suffix: "minsdk")
        defer { try? fm.removeItem(at: work) }

        var opts = baseOpts
        opts.minimumAPILevel = 21
        do {
            _ = try KSPackager.runAndroid(opts)
            Issue.record("Expected configInvalid")
        } catch let e as KSError {
            #expect(e.code == .configInvalid)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("targetSdk below minSdk is rejected")
    func targetSdkBelowMin() throws {
        let fm = FileManager.default
        let (work, baseOpts) = try makeFixture(suffix: "tgt")
        defer { try? fm.removeItem(at: work) }

        var opts = baseOpts
        opts.minimumAPILevel = 30
        opts.targetAPILevel = 26
        do {
            _ = try KSPackager.runAndroid(opts)
            Issue.record("Expected configInvalid")
        } catch let e as KSError {
            #expect(e.code == .configInvalid)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - applicationId validator unit

    @Test("isValidPackageIdentifier accepts canonical forms and rejects edge cases")
    func identifierValidator() {
        #expect(KSPackager.isValidPackageIdentifier("com.example.app"))
        #expect(KSPackager.isValidPackageIdentifier("dev.kalsae.demo"))
        #expect(KSPackager.isValidPackageIdentifier("a.b"))
        #expect(KSPackager.isValidPackageIdentifier("io.foo_bar.baz2"))

        #expect(!KSPackager.isValidPackageIdentifier(""))
        #expect(!KSPackager.isValidPackageIdentifier("single"))
        #expect(!KSPackager.isValidPackageIdentifier("Com.Example.App"))  // uppercase
        #expect(!KSPackager.isValidPackageIdentifier("1com.example.app"))  // digit-leading
        #expect(!KSPackager.isValidPackageIdentifier("com..example"))  // empty segment
        #expect(!KSPackager.isValidPackageIdentifier("com.example-app"))  // hyphen
    }

    // MARK: - Frontend dist optional

    @Test("Missing frontend dist surfaces a warning but does not fail")
    func missingFrontendWarns() throws {
        let fm = FileManager.default
        let (work, baseOpts) = try makeFixture(suffix: "no-dist")
        defer { try? fm.removeItem(at: work) }

        var opts = baseOpts
        opts.frontendDist = nil
        let report = try KSPackager.runAndroid(opts)
        #expect(report.warnings.contains(where: { $0.contains("Frontend dist") }))
    }
}
