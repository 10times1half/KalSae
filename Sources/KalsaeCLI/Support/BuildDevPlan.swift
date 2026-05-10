public import Foundation
public import KalsaeCore

public enum KSBuildPlanError: Error, CustomStringConvertible {
    case distNotFound(String)
    case distEmpty(String)
    case missingIndex(String)

    public var description: String {
        switch self {
        case .distNotFound(let path):
            return
                "Frontend dist directory not found at \(path). Run your frontend build first or pass --allow-missing-dist."
        case .distEmpty(let path):
            return
                "Frontend dist directory is empty at \(path). Run your frontend build first or pass --allow-missing-dist."
        case .missingIndex(let path):
            return
                "Frontend dist at \(path) does not contain index.html. Kalsae loads index.html as the entry point — run your frontend build or pass --allow-missing-dist."
        }
    }
}
public enum KSBuildPlan {
    public static func normalizedCommand(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }
        return raw
    }

    public static func swiftBuildArguments(debug: Bool, target: String?, jobs: Int? = nil) -> [String] {
        var args = ["build", "-c", debug ? "debug" : "release"]
        if let target {
            args += ["--target", target]
        }
        if let jobs {
            args += ["-j", "\(jobs)"]
        }
        return args
    }

    public static func resolveDistURL(
        config: KSConfig,
        configURL: URL,
        cwd: URL,
        distOverride: String?
    ) -> URL {
        if let distOverride {
            return URL(fileURLWithPath: distOverride, relativeTo: cwd)
                .standardizedFileURL
        }
        // `frontendDist` 가 `..` 세그먼트를 포함할 수 있으므로 (예: 템플릿 기본값
        // `"../../../dist"` — kalsae.json 은 `Sources/<NAME>/Resources/` 에 있고
        // vite outDir 은 프로젝트 루트의 `dist/`) standardize 로 `..` 를 collapse
        // 해야 한다. Windows 의 `contentsOfDirectory` 는 `..` 가 그대로 남은 URL 에서
        // 빈 결과를 돌려줘 "dist empty" 오진을 일으킨다.
        return configURL.deletingLastPathComponent()
            .appendingPathComponent(config.build.frontendDist)
            .standardizedFileURL
    }

    public static func validateFrontendDist(
        at distURL: URL,
        allowMissingDist: Bool,
        fm: FileManager = .default
    ) throws {
        if allowMissingDist { return }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: distURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw KSBuildPlanError.distNotFound(distURL.path)
        }

        let hasEntries =
            (try? fm.contentsOfDirectory(
                at: distURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]))?.isEmpty == false
        guard hasEntries else {
            throw KSBuildPlanError.distEmpty(distURL.path)
        }

        // index.html sanity check — Kalsae 의 가상 호스트는 항상 `index.html` 을
        // 엔트리로 로드한다 ([`KSApp+Boot.resolveStartURL`]). 빌드 산출물에
        // 없으면 런타임에 흰 화면이 되므로 빌드 시점에서 차단한다.
        let indexURL = distURL.appendingPathComponent("index.html")
        guard fm.fileExists(atPath: indexURL.path) else {
            throw KSBuildPlanError.missingIndex(distURL.path)
        }
    }
}
public struct KSDevPlan: Sendable {
    public var devCommand: String?
    public var shouldWaitForDevServer: Bool
    public var devServerURL: String?

    public init(devCommand: String?, shouldWaitForDevServer: Bool, devServerURL: String?) {
        self.devCommand = devCommand
        self.shouldWaitForDevServer = shouldWaitForDevServer
        self.devServerURL = devServerURL
    }

    public static func make(
        config: KSConfig?,
        skipDevCommand: Bool,
        noWaitDevServer: Bool,
        devServerURLOverride: String? = nil
    ) -> KSDevPlan {
        let command: String? = {
            guard !skipDevCommand else { return nil }
            return KSBuildPlan.normalizedCommand(config?.build.devCommand)
        }()

        let serverURL: String? = {
            if let raw = devServerURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty
            {
                return raw
            }
            return config?.build.devServerURL
        }()
        let shouldWait = !noWaitDevServer && isRemoteURL(serverURL)
        return KSDevPlan(
            devCommand: command,
            shouldWaitForDevServer: shouldWait,
            devServerURL: serverURL)
    }

    private static func isRemoteURL(_ text: String?) -> Bool {
        guard let text,
            let u = URL(string: text),
            let scheme = u.scheme?.lowercased()
        else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}

// MARK: - 설정 파일 위치 탐색

/// `kalsae.json` / `Kalsae.json` 을 찾는다. 우선순위:
/// 1. `cwd/Kalsae.json`
/// 2. `cwd/kalsae.json`
/// 3. `cwd/Sources/<*>/Resources/{Kalsae,kalsae}.json`
///
/// (3) 은 `kalsae new` 가 `Sources/<NAME>/Resources/` 에만
/// `kalsae.json` 을 쓰는 기본 동작과 호환을 위해 추가된 fallback.
public enum KSConfigLocator {
    public static func find(cwd: URL, fm: FileManager = .default) -> URL? {
        let names = ["Kalsae.json", "kalsae.json"]
        for n in names {
            let candidate = cwd.appendingPathComponent(n)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        let sources = cwd.appendingPathComponent("Sources")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sources.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            return nil
        }
        guard
            let entries = try? fm.contentsOfDirectory(
                at: sources,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else {
            return nil
        }
        // 다중 타겟 시 결정적 결과를 위해 정렬.
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let resources = entry.appendingPathComponent("Resources")
            for n in names {
                let candidate = resources.appendingPathComponent(n)
                if fm.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }
}
