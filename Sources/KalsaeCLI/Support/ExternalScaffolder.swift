/// 외부 스캐폴더(`npm create vite@latest`)를 호출해 프론트엔드 부분을
/// 생성한 뒤, Kalsae 전용 파일(`Package.swift`, `App.swift`, `kalsae.json`,
/// `.gitignore` 머지)을 위에 덮어쓰는 옵트인 경로.
///
/// `kalsae new <name> --frontend <react|vue|svelte> --use-external-scaffolder`
/// 가 켜졌을 때만 사용된다. 기본 경로는 여전히 내장 `Templates/` 사용.
public import Foundation
internal import KalsaeCore

public enum KSExternalScaffolderError: Error, CustomStringConvertible {
    case unsupportedFrontend(String)
    case toolNotFound(String)
    case viteCreateFailed(Int32)
    case viteOutputMissing(URL)

    public var description: String {
        switch self {
        case .unsupportedFrontend(let f):
            return "External scaffolder does not support frontend '\(f)'. "
                + "Use --frontend react|vue|svelte, or omit --use-external-scaffolder."
        case .toolNotFound(let t):
            return "Required tool '\(t)' was not found in PATH. "
                + "Install Node.js (https://nodejs.org/) and ensure '\(t)' is on PATH."
        case .viteCreateFailed(let code):
            return "'npm create vite@latest' exited with code \(code)."
        case .viteOutputMissing(let url):
            return "Expected scaffolder output at \(url.path) but the directory was not created."
        }
    }
}

public struct KSExternalScaffolder {
    public let name: String
    public let frontend: String
    public let packageManager: String
    public let kalsaePath: String?

    public init(
        name: String,
        frontend: String,
        packageManager: String = "npm",
        kalsaePath: String? = nil
    ) {
        self.name = name
        self.frontend = frontend
        self.packageManager = packageManager
        self.kalsaePath = kalsaePath
    }

    /// vite 프리셋 이름. TypeScript 변형을 기본으로 채택한다.
    private var vitePreset: String? {
        switch frontend.lowercased() {
        case "react": return "react-ts"
        case "vue": return "vue-ts"
        case "svelte": return "svelte-ts"
        default: return nil
        }
    }

    /// 외부 스캐폴더로 `parent/<name>/` 디렉터리를 생성한다.
    /// - Parameter parent: `<name>` 디렉터리가 만들어질 부모 디렉터리.
    public func scaffold(in parent: URL) throws {
        guard let preset = vitePreset else {
            throw KSExternalScaffolderError.unsupportedFrontend(frontend)
        }
        guard findExecutable(named: "npm") != nil else {
            throw KSExternalScaffolderError.toolNotFound("npm")
        }

        // `npm create vite@latest <name> -- --template <preset>`
        // `--` 이후 인자는 create-vite 본체에 전달된다.
        do {
            try shell(
                command: "npm",
                arguments: [
                    "create", "vite@latest", name,
                    "--", "--template", preset,
                ],
                in: parent.path)
        } catch ShellError.nonZeroExit(let code) {
            throw KSExternalScaffolderError.viteCreateFailed(code)
        }

        let dest = parent.appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dest.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            throw KSExternalScaffolderError.viteOutputMissing(dest)
        }

        try writeKalsaeOverlay(into: dest)
        try patchViteConfig(in: dest)
        try mergeGitignore(in: dest)
    }

    // MARK: - Overlay

    /// Kalsae 백엔드를 vite 프로젝트 위에 덮어쓴다.
    /// 동일 파일이 이미 존재하면 (예: `index.html`) **건드리지 않는다** —
    /// vite가 만든 파일이 우선이며, 우리는 추가 파일만 작성한다.
    internal func writeKalsaeOverlay(into dest: URL) throws {
        let template = ProjectTemplate(
            name: name,
            frontend: frontend,
            packageManager: packageManager,
            kalsaePath: kalsaePath)

        let sources = dest.appendingPathComponent("Sources").appendingPathComponent(name)
        let resources = sources.appendingPathComponent("Resources")
        let fm = FileManager.default
        try fm.createDirectory(at: sources, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)

        try writeTemplate(
            resource: "Package.swift", subdirectory: nil,
            to: dest.appendingPathComponent("Package.swift"),
            using: template)
        try writeTemplate(
            resource: "App.swift", subdirectory: nil,
            to: sources.appendingPathComponent("App.swift"),
            using: template)
        try writeTemplate(
            resource: "kalsae.json", subdirectory: nil,
            to: resources.appendingPathComponent("kalsae.json"),
            using: template)
    }

    private func writeTemplate(
        resource: String,
        subdirectory: String?,
        to destination: URL,
        using template: ProjectTemplate
    ) throws {
        let raw = try ProjectTemplate.loadTemplate(
            resource: resource, ext: "tmpl", subdirectory: subdirectory)
        let content = template.substitute(raw)
        try content.write(to: destination, atomically: false, encoding: .utf8)
    }

    // MARK: - vite.config 패치

    /// `vite.config.ts` 또는 `vite.config.js`에 `base: './'`를 주입한다.
    /// 이미 `base:` 키가 있으면 건드리지 않는다.
    /// `dist/` 산출물이 `ks://app/`/`file://`에서 모두 동작하려면 상대 경로
    /// (`base: './'`)가 필요하다.
    internal func patchViteConfig(in dest: URL) throws {
        let candidates = ["vite.config.ts", "vite.config.js", "vite.config.mts"]
        let fm = FileManager.default
        for name in candidates {
            let url = dest.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            let raw = try String(contentsOf: url, encoding: .utf8)
            if raw.contains("base:") { return }
            // `defineConfig({` 다음 줄에 `  base: './',` 삽입.
            // create-vite가 생성하는 표준 시그니처이므로 정규식 없이 첫 매치만 치환.
            let needle = "defineConfig({"
            guard let range = raw.range(of: needle) else { return }
            let replacement = "defineConfig({\n  base: './',"
            let patched = raw.replacingCharacters(in: range, with: replacement)
            try patched.write(to: url, atomically: false, encoding: .utf8)
            return
        }
    }

    // MARK: - .gitignore 머지

    /// vite가 만든 `.gitignore`에 `.build` / `.swiftpm` 등 SwiftPM 산출물을
    /// 추가한다. 이미 포함돼 있으면 스킵.
    internal func mergeGitignore(in dest: URL) throws {
        let url = dest.appendingPathComponent(".gitignore")
        let fm = FileManager.default
        let existing: String
        if fm.fileExists(atPath: url.path) {
            existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        } else {
            existing = ""
        }

        let entries = [".build", ".swiftpm", "*.xcodeproj", ".DS_Store"]
        var lines = existing.split(
            whereSeparator: { $0.isNewline }).map(String.init)
        var changed = false
        for entry in entries where !lines.contains(entry) {
            lines.append(entry)
            changed = true
        }
        if !changed { return }

        var output = lines.joined(separator: "\n")
        if !output.hasSuffix("\n") { output += "\n" }
        try output.write(to: url, atomically: false, encoding: .utf8)
    }
}
