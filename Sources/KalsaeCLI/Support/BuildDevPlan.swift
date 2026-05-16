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
        // `frontendDist` 는 일반적으로 kalsae.json 디렉터리 기준 상대 경로지만,
        // SwiftPM 템플릿은 kalsae.json 을 `Sources/<NAME>/Resources/` 에 두므로
        // 이 경우 *프로젝트 루트* 기준으로 해석한다. 즉:
        //
        //   <root>/Sources/<NAME>/Resources/kalsae.json + "dist"
        //     → <root>/dist
        //
        // 이 자동 보정 덕분에 새 템플릿은 `frontendDist: "dist"` 를 그대로 쓸 수 있다.
        let baseDir = configDirForFrontendDist(configURL: configURL)
        return
            baseDir
            .appendingPathComponent(config.build.frontendDist)
            .standardizedFileURL
    }

    /// `frontendDist` 가 해석되는 기준 디렉터리. configURL 이
    /// `.../Sources/<NAME>/Resources/kalsae.json` 형태이면 프로젝트 루트
    /// (`.../`) 를 반환하고, 그 외에는 configURL 의 상위 디렉터리를 반환한다.
    private static func configDirForFrontendDist(configURL: URL) -> URL {
        let dir = configURL.deletingLastPathComponent()
        // 패턴: */Sources/*/Resources
        let comps = dir.pathComponents
        if comps.count >= 4,
            comps[comps.count - 1] == "Resources",
            comps[comps.count - 3] == "Sources"
        {
            return
                dir
                .deletingLastPathComponent()  // strip Resources
                .deletingLastPathComponent()  // strip <NAME>
                .deletingLastPathComponent()  // strip Sources
        }
        return dir
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

/// `kalsae.json` 을 찾는다. 우선순위:
/// 1. `cwd/kalsae.json`
/// 2. `cwd/Sources/<*>/Resources/kalsae.json`
///
/// (2) 는 `kalsae new` 가 `Sources/<NAME>/Resources/` 에만
/// `kalsae.json` 을 쓰는 기본 동작과 호환을 위해 추가된 fallback.
public enum KSConfigLocator {
    public static let fileName = "kalsae.json"

    public static func find(cwd: URL, fm: FileManager = .default) -> URL? {
        let candidate = cwd.appendingPathComponent(Self.fileName)
        if fm.fileExists(atPath: candidate.path) { return candidate }
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
            let nested = resources.appendingPathComponent(Self.fileName)
            if fm.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }
}
