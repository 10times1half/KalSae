import Foundation
import KalsaeCore
import Testing

@testable import KalsaeCLICore

@Suite("ProjectTemplate")
struct ProjectTemplateTests {

    // MARK: - 헬퍼

    private func scaffold(
        name: String = "MyApp",
        frontend: String = "vanilla",
        packageManager: String = "npm",
        kalsaePath: String? = nil
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kalsae-test-\(UUID().uuidString)")
        try ProjectTemplate(
            name: name,
            frontend: frontend,
            packageManager: packageManager,
            kalsaePath: kalsaePath
        ).write(to: tmp)
        return tmp
    }

    // MARK: - 파일 트리

    @Test("Scaffold creates expected files")
    func scaffoldCreatesExpectedFiles() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        let base = root.appendingPathComponent("Sources/MyApp")
        let res = base.appendingPathComponent("Resources")

        #expect(fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path))
        #expect(fm.fileExists(atPath: base.appendingPathComponent("App.swift").path))
        #expect(fm.fileExists(atPath: res.appendingPathComponent("kalsae.json").path))
        #expect(fm.fileExists(atPath: res.appendingPathComponent("index.html").path))
    }

    // MARK: - index.html JS 브리지

    @Test("index.html uses window.__KS_ (not window.__kb)")
    func indexHTMLUsesCorrectGlobal() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let htmlURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/index.html")
        let html = try String(contentsOf: htmlURL, encoding: .utf8)

        #expect(html.contains("window.__KS_"), "Expected window.__KS_ in generated index.html")
        #expect(!html.contains("window.__kb."), "Found legacy window.__kb in generated index.html")
    }

    // MARK: - Kalsae.json

    @Test("Kalsae.json devServerURL defaults to about:blank for vanilla")
    func devServerURLDefault() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(
            json.contains("\"about:blank\""),
            "devServerURL should default to about:blank, got: \(json)")
        #expect(
            !json.contains("localhost:5173"),
            "devServerURL must not point at a dev server by default")
        #expect(
            json.contains("\"devCommand\": null"),
            "vanilla preset should have null devCommand")
        #expect(
            json.contains("\"buildCommand\": null"),
            "vanilla preset should have null buildCommand")
    }

    @Test("Kalsae.json contains commandAllowlist with hello")
    func commandAllowlist() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("commandAllowlist"), "Expected commandAllowlist in Kalsae.json")
        #expect(json.contains("\"hello\""), "Expected hello command in allowlist")
    }

    @Test("Kalsae.json encodes project name and identifier")
    func projectNameEmbedded() throws {
        let root = try scaffold(name: "CoolApp")
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/CoolApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("\"CoolApp\""), "App name missing from Kalsae.json")
        #expect(json.contains("dev.kalsae.coolapp"), "Identifier missing from Kalsae.json")
    }

    @Test("Generated files use shared Kalsae version")
    func generatedFilesUseSharedVersion() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let packageURL = root.appendingPathComponent("Package.swift")

        let json = try String(contentsOf: jsonURL, encoding: .utf8)
        let package = try String(contentsOf: packageURL, encoding: .utf8)

        #expect(
            json.contains("\"version\": \"\(KSVersion.current)\""),
            "generated Kalsae.json should use shared version")
        // 기본 템플릿은 `from: KSVersion.current` 의존성을 사용한다.
        // CKalsaeWV2 에서 unsafeFlags 를 제거했으므로 버전 태그 기반 의존성을 사용할 수 있다.
        #expect(
            package.contains("from: \"\(KSVersion.current)\""),
            "generated Package.swift should pin Kalsae to current version")
        #expect(
            package.contains("https://github.com/10times1half/KalSae.git"),
            "generated Package.swift should use canonical Kalsae repository URL")
    }

    @Test("kalsaePath produces a path-based Kalsae dependency")
    func kalsaePathProducesPathDependency() throws {
        let root = try scaffold(kalsaePath: "C:/Projects/Kalsae")
        defer { try? FileManager.default.removeItem(at: root) }

        let package = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(
            package.contains(".package(name: \"kalsae\", path: \"C:/Projects/Kalsae\")"),
            "kalsaePath should emit a SwiftPM path dependency, got: \(package)"
        )
        #expect(
            package.contains(".product(name: \"KalsaeMacros\", package: \"kalsae\")"),
            "generated Package.swift should depend on KalsaeMacros for @KSCommand support"
        )
        #expect(
            !package.contains("https://github.com/10times1half/KalSae.git"),
            "kalsaePath should suppress the canonical URL dependency"
        )
    }

    @Test("Generated Package.swift sets Windows GUI subsystem to hide console")
    func packageSwiftHasWindowsSubsystemFlag() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let package = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8)

        // 콘솔 창 방지: PE 서브시스템을 GUI 로 변경.
        #expect(
            package.contains("/SUBSYSTEM:WINDOWS"),
            "Package.swift must set /SUBSYSTEM:WINDOWS so packaged EXE doesn't open a console, got: \(package)")
        // wWinMain 부재로 LNK2019 가 나지 않게 CRT 진입점 명시.
        #expect(
            package.contains("/ENTRY:mainCRTStartup"),
            "Package.swift must set /ENTRY:mainCRTStartup for Swift @main, got: \(package)")
        #expect(
            package.contains(".when(platforms: [.windows])"),
            "Linker subsystem flags must be Windows-gated, got: \(package)")
    }

    @Test("Generated App.swift never feeds the buggy `configURL.deletingLastPathComponent()` as resourceRoot")
    func appSwiftHasNoResourceRoot() throws {
        let root = try scaffold()
        defer { try? FileManager.default.removeItem(at: root) }

        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/MyApp/App.swift"),
            encoding: .utf8)

        // resourceRoot 를 무조건 `configURL.deletingLastPathComponent()` 로 넘기면
        // 패키지 모드(EXE 옆 Kalsae.json + assets in `<exeDir>/<frontendDist>/`)에서
        // 흰화면이 된다. 새 템플릿은 패키지 모드에서 `nil` 을 넘겨 KSApp.boot 가
        // `<configDir>/<frontendDist>` 로 자동 해석하도록 위임한다.
        #expect(
            !app.contains("configURL.deletingLastPathComponent()"),
            "App.swift must not pass `configURL.deletingLastPathComponent()` as resourceRoot — that breaks packaged builds, got: \(app)"
        )
        #expect(
            app.contains("KSApp.bootFromBundle("),
            "App.swift should still call KSApp.bootFromBundle, got: \(app)")

        // `@KSCommand` 매크로 확장은 `Foundation.JSONDecoder` / `Foundation.Data` 등
        // `Foundation.*` 정규화 참조를 만들어내므로, 사용처 파일에 반드시
        // `import Foundation` 이 있어야 한다 (없으면 빌드 시 "cannot find 'Foundation'
        // in scope" 가 매크로 확장 위치에서 발생).
        #expect(
            app.contains("import Foundation"),
            "App.swift must `import Foundation` so @KSCommand expansion compiles, got: \(app)")
    }

    // MARK: - 프론트엔드 프리셋

    @Test("React preset writes dist/dev/build fields with specified package manager")
    func reactPresetWithPnpm() throws {
        let root = try scaffold(frontend: "react", packageManager: "pnpm")
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(
            json.contains("\"frontendDist\": \"dist\""),
            "react preset should set frontendDist to dist (resolved at runtime against project root)")
        #expect(json.contains("localhost:5173"), "react preset should set devServerURL")
        #expect(json.contains("\"devCommand\": \"pnpm run dev\""), "react preset should include pnpm dev command")
        #expect(json.contains("\"buildCommand\": \"pnpm run build\""), "react preset should include pnpm build command")
    }

    @Test("Vue preset with yarn uses yarn commands")
    func vuePresetWithYarn() throws {
        let root = try scaffold(frontend: "vue", packageManager: "yarn")
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("\"devCommand\": \"yarn run dev\""), "vue+yarn preset should use yarn dev")
        #expect(json.contains("\"buildCommand\": \"yarn run build\""), "vue+yarn preset should use yarn build")
    }

    @Test("Unknown frontend preset falls back to vanilla defaults")
    func unknownFrontendFallsBackToVanilla() throws {
        let root = try scaffold(frontend: "angular")  // unsupported — fallback
        defer { try? FileManager.default.removeItem(at: root) }

        let jsonURL =
            root
            .appendingPathComponent("Sources/MyApp/Resources/kalsae.json")
        let json = try String(contentsOf: jsonURL, encoding: .utf8)

        #expect(json.contains("\"about:blank\""), "unknown preset should fall back to vanilla")
        #expect(json.contains("\"devCommand\": null"), "unknown preset should have null devCommand")
    }

    // MARK: - React 인라인 프론트엔드 파일

    @Test("React preset scaffolds package.json + vite project files")
    func reactScaffoldsViteFiles() throws {
        let root = try scaffold(frontend: "react")
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: root.appendingPathComponent("package.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("vite.config.ts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("tsconfig.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("index.html").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/main.tsx").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/App.tsx").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/vite-env.d.ts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/index.css").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent(".gitignore").path))

        // ambient .d.ts는 Vite client 타입을 참조해 *.css side-effect import를
        // 풀어주어야 한다. 또한 baseName이 `App.tsx`와 충돌하지 않도록
        // `vite-env.d.ts` 명명을 유지한다 (Windows 대소문자 무시 FS 회귀).
        let viteEnv = try String(
            contentsOf: root.appendingPathComponent("src/vite-env.d.ts"), encoding: .utf8)
        #expect(
            viteEnv.contains("/// <reference types=\"vite/client\" />"),
            "react vite-env.d.ts must reference vite/client for CSS ambient modules, got: \(viteEnv)")
        #expect(
            viteEnv.contains("interface Window") && viteEnv.contains("__KS_"),
            "react vite-env.d.ts must declare Window.__KS_, got: \(viteEnv)")
    }

    @Test("React vite.config outputs into project-root dist")
    func reactViteOutDir() throws {
        let root = try scaffold(name: "CoolApp", frontend: "react")
        defer { try? FileManager.default.removeItem(at: root) }

        let viteConfig = try String(
            contentsOf: root.appendingPathComponent("vite.config.ts"), encoding: .utf8)
        #expect(
            viteConfig.contains("outDir: 'dist'"),
            "vite outDir must point at project-root dist, got: \(viteConfig)")
    }

    @Test("React package.json uses lowercase project name")
    func reactPackageJsonNameLowercased() throws {
        let root = try scaffold(name: "CoolApp", frontend: "react")
        defer { try? FileManager.default.removeItem(at: root) }

        let pkg = try String(
            contentsOf: root.appendingPathComponent("package.json"), encoding: .utf8)
        #expect(pkg.contains("\"name\": \"coolapp\""), "package.json name must be lowercased, got: \(pkg)")
    }

    // MARK: - Vue 인라인 프론트엔드 파일

    @Test("Vue preset scaffolds package.json + vite project files")
    func vueScaffoldsViteFiles() throws {
        let root = try scaffold(frontend: "vue")
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: root.appendingPathComponent("package.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("vite.config.ts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("tsconfig.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("tsconfig.app.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("tsconfig.node.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("index.html").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/main.ts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/App.vue").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/vite-env.d.ts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/style.css").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent(".gitignore").path))

        let viteEnv = try String(
            contentsOf: root.appendingPathComponent("src/vite-env.d.ts"), encoding: .utf8)
        #expect(
            viteEnv.contains("/// <reference types=\"vite/client\" />"),
            "vue vite-env.d.ts must reference vite/client for CSS ambient modules, got: \(viteEnv)")
        #expect(
            viteEnv.contains("interface Window") && viteEnv.contains("__KS_"),
            "vue vite-env.d.ts must declare Window.__KS_, got: \(viteEnv)")
    }

    @Test("Vue vite.config outputs into project-root dist")
    func vueViteOutDir() throws {
        let root = try scaffold(name: "CoolApp", frontend: "vue")
        defer { try? FileManager.default.removeItem(at: root) }

        let viteConfig = try String(
            contentsOf: root.appendingPathComponent("vite.config.ts"), encoding: .utf8)
        #expect(
            viteConfig.contains("outDir: 'dist'"),
            "vite outDir must point at project-root dist, got: \(viteConfig)")
    }

    @Test("Vue App.vue uses window.__KS_ bridge")
    func vueAppUsesBridge() throws {
        let root = try scaffold(name: "CoolApp", frontend: "vue")
        defer { try? FileManager.default.removeItem(at: root) }

        let app = try String(
            contentsOf: root.appendingPathComponent("src/App.vue"), encoding: .utf8)
        #expect(app.contains("window.__KS_"), "Vue App.vue must use window.__KS_ bridge")
        #expect(app.contains("CoolApp"), "Vue App.vue must include project name")
    }

    // MARK: - Svelte 인라인 프론트엔드 파일

    @Test("Svelte preset scaffolds package.json + vite project files")
    func svelteScaffoldsViteFiles() throws {
        let root = try scaffold(frontend: "svelte")
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: root.appendingPathComponent("package.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("vite.config.ts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("tsconfig.json").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("svelte.config.js").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("index.html").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/main.ts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/App.svelte").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/vite-env.d.ts").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/app.css").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent(".gitignore").path))

        let viteEnv = try String(
            contentsOf: root.appendingPathComponent("src/vite-env.d.ts"), encoding: .utf8)
        #expect(
            viteEnv.contains("/// <reference types=\"vite/client\" />"),
            "svelte vite-env.d.ts must reference vite/client for CSS ambient modules, got: \(viteEnv)")
        #expect(
            viteEnv.contains("interface Window") && viteEnv.contains("__KS_"),
            "svelte vite-env.d.ts must declare Window.__KS_, got: \(viteEnv)")
    }

    @Test("Svelte vite.config outputs into project-root dist")
    func svelteViteOutDir() throws {
        let root = try scaffold(name: "CoolApp", frontend: "svelte")
        defer { try? FileManager.default.removeItem(at: root) }

        let viteConfig = try String(
            contentsOf: root.appendingPathComponent("vite.config.ts"), encoding: .utf8)
        #expect(
            viteConfig.contains("outDir: 'dist'"),
            "vite outDir must point at project-root dist, got: \(viteConfig)")
    }

    @Test("Svelte App.svelte uses window.__KS_ bridge")
    func svelteAppUsesBridge() throws {
        let root = try scaffold(name: "CoolApp", frontend: "svelte")
        defer { try? FileManager.default.removeItem(at: root) }

        let app = try String(
            contentsOf: root.appendingPathComponent("src/App.svelte"), encoding: .utf8)
        #expect(app.contains("window.__KS_"), "Svelte App.svelte must use window.__KS_ bridge")
        #expect(app.contains("CoolApp"), "Svelte App.svelte must include project name")
    }
}

// MARK: - KSConfigLocator

@Suite("KSConfigLocator")
struct KSConfigLocatorTests {
    @Test("Finds Sources/<name>/Resources/kalsae.json fallback")
    func findsResourcesFallback() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kalsae-locator-\(UUID().uuidString)")
        try ProjectTemplate(name: "MyApp").write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let found = KSConfigLocator.find(cwd: tmp)
        #expect(found != nil, "Should locate kalsae.json under Sources/MyApp/Resources/")
        // Windows 는 대소문자 무시 파일시스템이므로 KSConfigLocator 가 시도하는 첫
        // 후보(Kalsae.json) 가 그대로 일치할 수 있다. 두 표기 모두 허용.
        let lower = found?.lastPathComponent.lowercased()
        #expect(lower == "kalsae.json")
    }

    @Test("Prefers root-level kalsae.json over Resources fallback")
    func prefersRootLevel() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kalsae-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let rootCfg = tmp.appendingPathComponent("kalsae.json")
        try "{}".write(to: rootCfg, atomically: false, encoding: .utf8)

        // Sources/X/Resources/kalsae.json 도 만든다.
        let sub = tmp.appendingPathComponent("Sources/X/Resources")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "{}".write(
            to: sub.appendingPathComponent("kalsae.json"),
            atomically: false, encoding: .utf8)

        let found = KSConfigLocator.find(cwd: tmp)
        #expect(found?.path == rootCfg.path, "Root-level kalsae.json should win")
    }

    @Test("Returns nil when no config exists")
    func returnsNil() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kalsae-locator-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(KSConfigLocator.find(cwd: tmp) == nil)
    }
}
