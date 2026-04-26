public import Foundation

/// Generates the file tree for a freshly scaffolded Kalsae project.
///
/// Templates live as resource files under `Support/Templates/*.tmpl` so
/// non-Swift authors (e.g. translators, designers) can edit them
/// without recompiling, and the source files round-trip cleanly through
/// editors that would otherwise mangle escaped strings.
public struct ProjectTemplate {
    public let name: String

    public init(name: String) { self.name = name }

    /// Reverse-DNS bundle identifier derived from the project name.
    private var identifier: String {
        let slug = name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "dev.kalsae.\(slug)"
    }

    /// Errors specific to template materialisation. Surface as the
    /// caller's `Error` (typically `ValidationError` once boxed).
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

    // MARK: - Write

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
            try content.write(to: dest, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Substitution

    /// Replaces `{{NAME}}` and `{{IDENTIFIER}}` placeholders. New
    /// placeholders should be added here and documented alongside the
    /// template files — this is the only place the CLI substitutes.
    func substitute(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "{{NAME}}", with: name)
            .replacingOccurrences(of: "{{IDENTIFIER}}", with: identifier)
    }

    // MARK: - Resource loading

    /// Loads `<resource>.<ext>` from this module's resource bundle.
    /// `internal` so unit tests can exercise the same lookup path
    /// the runtime uses.
    static func loadTemplate(resource: String, ext: String) throws -> String {
        guard let url = Bundle.module.url(
            forResource: resource, withExtension: ext, subdirectory: "Templates")
        else {
            throw TemplateError.missingResource("\(resource).\(ext)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
