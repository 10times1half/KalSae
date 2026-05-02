public import Foundation
public import KalsaeCore

public enum KSBuildPlanError: Error, CustomStringConvertible {
    case distNotFound(String)
    case distEmpty(String)

    public var description: String {
        switch self {
        case .distNotFound(let path):
            return
                "Frontend dist directory not found at \(path). Run your frontend build first or pass --allow-missing-dist."
        case .distEmpty(let path):
            return
                "Frontend dist directory is empty at \(path). Run your frontend build first or pass --allow-missing-dist."
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

    public static func swiftBuildArguments(debug: Bool, target: String?) -> [String] {
        var args = ["build", "-c", debug ? "debug" : "release"]
        if let target {
            args += ["--target", target]
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
        }
        return configURL.deletingLastPathComponent().appendingPathComponent(config.build.frontendDist)
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
        noWaitDevServer: Bool
    ) -> KSDevPlan {
        let command: String? = {
            guard !skipDevCommand else { return nil }
            return KSBuildPlan.normalizedCommand(config?.build.devCommand)
        }()

        let serverURL = config?.build.devServerURL
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
