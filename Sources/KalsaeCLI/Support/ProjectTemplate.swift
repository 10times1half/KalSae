public import Foundation

/// 새로 스케폴딩된 Kalsae 프로젝트의 파일 트리를 생성한다.
///
/// 템플릿은 `Support/Templates/*.tmpl` 리소스 파일로 저장되어
/// Swift가 아닌 저자 (e.g. 번역가, 디자이너)들이
/// 재컴파일 없이 편집할 수 있으며, 소스 파일이 이스케이프된 문자열을
/// 왜곡시킬 수 있는 편집기를 통해서도 정상적으로 라운드트립한다.
public struct ProjectTemplate {
    public let name: String
    public let frontend: String
    public let packageManager: String

    public init(name: String, frontend: String = "vanilla", packageManager: String = "npm") {
        self.name = name
        self.frontend = frontend
        self.packageManager = packageManager
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
                return "Bundled template resource '\(name)' is missing. " +
                    "This is a build-time bug — please report it."
            }
        }
    }

    // MARK: - 쓰기

    public func write(to directory: URL) throws {
        let fm = FileManager.default

        // 디렉터리 트리
        let sourcesDir   = directory.appendingPathComponent("Sources")
            .appendingPathComponent(name)
        let resourcesDir = sourcesDir.appendingPathComponent("Resources")
        try fm.createDirectory(at: directory,    withIntermediateDirectories: true)
        try fm.createDirectory(at: sourcesDir,   withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        // 출력 매핑: 템플릿 리소스 이름 → 결과 경로.
        let mapping: [(resource: String, ext: String, destination: URL)] = [
            ("Package.swift", "tmpl",
             directory.appendingPathComponent("Package.swift")),
            ("App.swift", "tmpl",
             sourcesDir.appendingPathComponent("App.swift")),
            ("kalsae.json", "tmpl",
             resourcesDir.appendingPathComponent("kalsae.json")),
            ("index.html", "tmpl",
             resourcesDir.appendingPathComponent("index.html")),
        ]

        for (resource, ext, dest) in mapping {
            let raw = try Self.loadTemplate(resource: resource, ext: ext)
            let content = substitute(raw)
            // atomically: false — Windows에서 atomically: true는 같은 디렉터리에
            // 임시 파일을 생성한 뒤 rename하므로 Defender/Indexer와 충돌해
            // ERROR_SHARING_VIOLATION (Win32 32)이 발생한다.
            try content.write(to: dest, atomically: false, encoding: .utf8)
        }
    }

    // MARK: - 치환

    /// 플레이스홀더를 실제 값으로 대체한다.
    /// `{{NAME}}`, `{{IDENTIFIER}}`, `{{FRONTEND_DIST}}`, `{{DEV_SERVER_URL}}`,
    /// `{{DEV_COMMAND}}`, `{{BUILD_COMMAND}}` 를 처리한다.
    func substitute(_ raw: String) -> String {
        let b = buildDefaults
        let devCommandJSON  = b.devCommand.map  { "\"\($0)\"" } ?? "null"
        let buildCommandJSON = b.buildCommand.map { "\"\($0)\"" } ?? "null"
        return raw
            .replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{IDENTIFIER}}", with: identifier)
            .replacingOccurrences(of: "{{FRONTEND_DIST}}", with: b.frontendDist)
            .replacingOccurrences(of: "{{DEV_SERVER_URL}}", with: b.devServerURL)
            .replacingOccurrences(of: "{{DEV_COMMAND}}", with: devCommandJSON)
            .replacingOccurrences(of: "{{BUILD_COMMAND}}", with: buildCommandJSON)
    }

    // MARK: - 리소스 로딩

    /// 이 모듈의 리소스 번들에서 `<resource>.<ext>`를 로드한다.
    /// 런타임이 사용하는 동일한 름업 경로를 단위 테스트가 확인할 수 있도록 `internal`로 유지한다.
    static func loadTemplate(resource: String, ext: String) throws -> String {
        guard let url = Bundle.module.url(
            forResource: resource, withExtension: ext, subdirectory: "Templates")
        else {
            throw TemplateError.missingResource("\(resource).\(ext)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
