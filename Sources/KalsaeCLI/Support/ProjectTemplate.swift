/// 새로 스케폴딩된 Kalsae 프로젝트의 파일 트리를 생성한다.
///
/// 템플릿은 `Support/Templates/*.tmpl` 리소스 파일로 저장되어
/// Swift가 아닌 저자 (e.g. 번역가, 디자이너)들이
/// 재컴파일 없이 편집할 수 있으며, 소스 파일이 이스케이프된 문자열을
/// 왜곡시킬 수 있는 편집기를 통해서도 정상적으로 라운드트립한다.
public import Foundation
internal import KalsaeCore

public struct ProjectTemplate {
    public let name: String
    public let frontend: String
    public let packageManager: String
    public let kalsaePath: String?

    public init(
        name: String,
        frontend: String = "vanilla",
        packageManager: String = "npm",
        kalsaePath: String? = nil
    ) {
        self.name = name
        self.frontend = frontend
        self.packageManager = packageManager
        self.kalsaePath = kalsaePath
    }

    private struct BuildDefaults {
        let frontendDist: String
        let devServerURL: String
        let devCommand: String?
        let buildCommand: String?
    }

    private var buildDefaults: BuildDefaults {
        switch frontend.lowercased() {
        case "react", "vue", "svelte":
            let pm = packageManager.lowercased()
            return BuildDefaults(
                frontendDist: "dist",
                devServerURL: "http://localhost:5173",
                devCommand: "\(pm) run dev",
                buildCommand: "\(pm) run build"
            )
        default:
            return BuildDefaults(
                frontendDist: "Resources",
                devServerURL: "about:blank",
                devCommand: nil,
                buildCommand: nil
            )
        }
    }

    /// 프로젝트 이름에서 유도된 역 DNS 번들 식별자.
    private var identifier: String {
        let slug = name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "dev.kalsae.\(slug)"
    }

    /// 템플릿 구체화에 특하는 오류.
    /// 호출자의 `Error` (일반적으로 상자에 담기면 `ValidationError`)로
    /// 표면된다.
    public enum TemplateError: Error, CustomStringConvertible {
        case missingResource(String)

        public var description: String {
            switch self {
            case .missingResource(let name):
                return "Bundled template resource '\(name)' is missing. "
                    + "This is a build-time bug — please report it."
            }
        }
    }

    // MARK: - 쓰기

    public func write(to directory: URL) throws {
        let fm = FileManager.default

        // 디렉터리 트리
        let sourcesDir = directory.appendingPathComponent("Sources")
            .appendingPathComponent(name)
        let resourcesDir = sourcesDir.appendingPathComponent("Resources")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        // 공통 출력 매핑: 다음 파일들은 어떤 프론트엔드에서도 쓰인다.
        var mapping: [TemplateMapping] = [
            .init(
                resource: "Package.swift", ext: "tmpl", subdirectory: nil,
                destination: directory.appendingPathComponent("Package.swift")),
            .init(
                resource: "App.swift", ext: "tmpl", subdirectory: nil,
                destination: sourcesDir.appendingPathComponent("App.swift")),
            .init(
                resource: "kalsae.json", ext: "tmpl", subdirectory: nil,
                destination: resourcesDir.appendingPathComponent("kalsae.json")),
        ]

        // 프론트엔드에 따라 프로젝트 루트에 프론트엔드 소스를 생성한다.
        switch frontend.lowercased() {
        case "react":
            mapping += [
                .init(
                    resource: "package.json", ext: "tmpl", subdirectory: "react",
                    destination: directory.appendingPathComponent("package.json")),
                .init(
                    resource: "vite.config.ts", ext: "tmpl", subdirectory: "react",
                    destination: directory.appendingPathComponent("vite.config.ts")),
                .init(
                    resource: "tsconfig.json", ext: "tmpl", subdirectory: "react",
                    destination: directory.appendingPathComponent("tsconfig.json")),
                .init(
                    resource: "tsconfig.node.json", ext: "tmpl", subdirectory: "react",
                    destination: directory.appendingPathComponent("tsconfig.node.json")),
                .init(
                    resource: "index.html", ext: "tmpl", subdirectory: "react",
                    destination: directory.appendingPathComponent("index.html")),
                .init(
                    resource: "main.tsx", ext: "tmpl", subdirectory: "react",
                    destination: directory.appendingPathComponent("src/main.tsx")),
                .init(
                    resource: "App.tsx", ext: "tmpl", subdirectory: "react",
                    destination: directory.appendingPathComponent("src/App.tsx")),
                .init(
                    resource: "index.css", ext: "tmpl", subdirectory: "react",
                    destination: directory.appendingPathComponent("src/index.css")),
                .init(
                    resource: "gitignore", ext: "tmpl", subdirectory: "common",
                    destination: directory.appendingPathComponent(".gitignore")),
            ]
        case "vue":
            mapping += [
                .init(
                    resource: "package.json", ext: "tmpl", subdirectory: "vue",
                    destination: directory.appendingPathComponent("package.json")),
                .init(
                    resource: "vite.config.ts", ext: "tmpl", subdirectory: "vue",
                    destination: directory.appendingPathComponent("vite.config.ts")),
                .init(
                    resource: "tsconfig.json", ext: "tmpl", subdirectory: "vue",
                    destination: directory.appendingPathComponent("tsconfig.json")),
                .init(
                    resource: "tsconfig.app.json", ext: "tmpl", subdirectory: "vue",
                    destination: directory.appendingPathComponent("tsconfig.app.json")),
                .init(
                    resource: "tsconfig.node.json", ext: "tmpl", subdirectory: "vue",
                    destination: directory.appendingPathComponent("tsconfig.node.json")),
                .init(
                    resource: "index.html", ext: "tmpl", subdirectory: "vue",
                    destination: directory.appendingPathComponent("index.html")),
                .init(
                    resource: "main.ts", ext: "tmpl", subdirectory: "vue",
                    destination: directory.appendingPathComponent("src/main.ts")),
                .init(
                    resource: "App.vue", ext: "tmpl", subdirectory: "vue",
                    destination: directory.appendingPathComponent("src/App.vue")),
                .init(
                    resource: "style.css", ext: "tmpl", subdirectory: "vue",
                    destination: directory.appendingPathComponent("src/style.css")),
                .init(
                    resource: "gitignore", ext: "tmpl", subdirectory: "common",
                    destination: directory.appendingPathComponent(".gitignore")),
            ]
        case "svelte":
            mapping += [
                .init(
                    resource: "package.json", ext: "tmpl", subdirectory: "svelte",
                    destination: directory.appendingPathComponent("package.json")),
                .init(
                    resource: "vite.config.ts", ext: "tmpl", subdirectory: "svelte",
                    destination: directory.appendingPathComponent("vite.config.ts")),
                .init(
                    resource: "tsconfig.json", ext: "tmpl", subdirectory: "svelte",
                    destination: directory.appendingPathComponent("tsconfig.json")),
                .init(
                    resource: "svelte.config.js", ext: "tmpl", subdirectory: "svelte",
                    destination: directory.appendingPathComponent("svelte.config.js")),
                .init(
                    resource: "index.html", ext: "tmpl", subdirectory: "svelte",
                    destination: directory.appendingPathComponent("index.html")),
                .init(
                    resource: "main.ts", ext: "tmpl", subdirectory: "svelte",
                    destination: directory.appendingPathComponent("src/main.ts")),
                .init(
                    resource: "App.svelte", ext: "tmpl", subdirectory: "svelte",
                    destination: directory.appendingPathComponent("src/App.svelte")),
                .init(
                    resource: "app.css", ext: "tmpl", subdirectory: "svelte",
                    destination: directory.appendingPathComponent("src/app.css")),
                .init(
                    resource: "gitignore", ext: "tmpl", subdirectory: "common",
                    destination: directory.appendingPathComponent(".gitignore")),
            ]
        default:
            // vanilla: 단일 index.html.
            mapping.append(
                .init(
                    resource: "index.html", ext: "tmpl", subdirectory: nil,
                    destination: resourcesDir.appendingPathComponent("index.html"))
            )
        }

        for entry in mapping {
            let raw = try Self.loadTemplate(
                resource: entry.resource, ext: entry.ext, subdirectory: entry.subdirectory)
            let content = substitute(raw)
            try fm.createDirectory(
                at: entry.destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            // atomically: false — Windows에서 atomically: true는 같은 디렉터리에
            // 임시 파일을 생성한 뒤 rename하므로 Defender/Indexer와 충돌해
            // ERROR_SHARING_VIOLATION (Win32 32)이 발생한다.
            try content.write(to: entry.destination, atomically: false, encoding: .utf8)
        }
    }

    private struct TemplateMapping {
        let resource: String
        let ext: String
        let subdirectory: String?
        let destination: URL
    }

    // MARK: - 치환

    /// 플레이스홀더를 실제 값으로 대체한다.
    /// `{{NAME}}`, `{{IDENTIFIER}}`, `{{FRONTEND_DIST}}`, `{{DEV_SERVER_URL}}`,
    /// `{{DEV_COMMAND}}`, `{{BUILD_COMMAND}}`, `{{APP_VERSION}}`,
    /// `{{KALSAE_VERSION}}` 를 처리한다.
    func substitute(_ raw: String) -> String {
        let b = buildDefaults
        let devCommandJSON = b.devCommand.map { "\"\($0)\"" } ?? "null"
        let buildCommandJSON = b.buildCommand.map { "\"\($0)\"" } ?? "null"
        return
            raw
            .replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{NAME_LOWER}}", with: name.lowercased())
            .replacingOccurrences(of: "{{IDENTIFIER}}", with: identifier)
            .replacingOccurrences(of: "{{FRONTEND_DIST}}", with: b.frontendDist)
            .replacingOccurrences(of: "{{DEV_SERVER_URL}}", with: b.devServerURL)
            .replacingOccurrences(of: "{{DEV_COMMAND}}", with: devCommandJSON)
            .replacingOccurrences(of: "{{BUILD_COMMAND}}", with: buildCommandJSON)
            .replacingOccurrences(of: "{{APP_VERSION}}", with: KSVersion.current)
            .replacingOccurrences(of: "{{KALSAE_VERSION}}", with: KSVersion.current)
            .replacingOccurrences(of: "{{KALSAE_DEPENDENCY}}", with: kalsaeDependencyLine)
    }

    /// `Package.swift` 의 `dependencies:` 배열에 들어갈 한 줄.
    /// - `kalsaePath` 가 주어지면 로컬 경로 의존성을 생성한다 (로컬 개발용).
    /// - 그렇지 않으면 표준 GitHub URL 의존성을 `from: KSVersion.current` 로 생성한다.
    private var kalsaeDependencyLine: String {
        if let path = kalsaePath, !path.isEmpty {
            // Package.swift 는 슬래시 구분자를 기대한다 (Windows 백슬래시 회피).
            let normalized = path.replacingOccurrences(of: "\\", with: "/")
            // 따옴표/백슬래시 이스케이프.
            let escaped =
                normalized
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return ".package(name: \"kalsae\", path: \"\(escaped)\"),"
        }
        return ".package(url: \"https://github.com/10times1half/KalSae.git\", from: \"\(KSVersion.current)\"),"
    }

    // MARK: - 리소스 로딩

    /// 이 모듈의 리소스 번들에서 `<resource>.<ext>`를 로드한다.
    /// 런타임이 사용하는 동일한 름업 경로를 단위 테스트가 확인할 수 있도록 `internal`로 유지한다.
    static func loadTemplate(resource: String, ext: String, subdirectory: String? = nil)
        throws -> String
    {
        let lookupSubdir = subdirectory.map { "Templates/\($0)" } ?? "Templates"
        guard
            let url = Bundle.module.url(
                forResource: resource, withExtension: ext, subdirectory: lookupSubdir)
        else {
            throw TemplateError.missingResource("\(lookupSubdir)/\(resource).\(ext)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
