public import Foundation
public import KalsaeCore

/// `kalsae build` 명령의 빌드 계획 수립 중 발생할 수 있는 오류를 나타냅니다.
///
/// 프론트엔드 빌드 산출물(`dist` 디렉터리)의 유효성 검사 과정에서
/// 발생하는 세 가지 유형의 오류를 정의합니다:
/// - 디렉터리가 아예 존재하지 않는 경우
/// - 디렉터리는 있지만 비어 있는 경우
/// - `index.html`이 누락된 경우
public enum KSBuildPlanError: Error, CustomStringConvertible {
    /// 프론트엔드 빌드 산출물 디렉터리가 존재하지 않습니다.
    case distNotFound(String)
    /// 프론트엔드 빌드 산출물 디렉터리가 비어 있습니다.
    case distEmpty(String)
    /// 프론트엔드 빌드 산출물에 `index.html`이 없습니다.
    case missingIndex(String)

    /// 사람이 읽을 수 있는 오류 메시지를 반환합니다.
    /// 각 오류 케이스에 따라 사용자에게 명확한 해결 방안을 안내합니다.
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

/// `kalsae build` 및 `kalsae dev` 명령이 사용하는 빌드 계획 관련 유틸리티 함수 모음입니다.
///
/// 프론트엔드 빌드 설정 정규화, Swift 빌드 인자 구성, `dist` 디렉터리 URL 해석,
/// 프론트엔드 산출물 유효성 검사 등의 기능을 제공합니다.
public enum KSBuildPlan {
    /// dev/build 명령어 문자열을 정규화합니다.
    /// 앞뒤 공백을 제거하고 빈 문자열은 `nil`로 변환합니다.
    /// - Parameter raw: 원시 명령어 문자열 (예: `"  npm run dev  "`)
    /// - Returns: 정규화된 명령어 문자열 (비어 있거나 공백만 있으면 `nil`)
    public static func normalizedCommand(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else {
            return nil
        }
        return raw
    }

    /// `swift build` 명령행 인자 배열을 생성합니다.
    /// 디버그/릴리스 모드, 대상(target), 병렬 작업 수를 지정할 수 있습니다.
    /// - Parameters:
    ///   - debug: `true`이면 debug 모드, `false`이면 release 모드
    ///   - target: 빌드할 SwiftPM 타겟 이름 (선택 사항)
    ///   - jobs: 병렬 빌드 작업 수 (선택 사항, nil이면 SwiftPM 기본값 사용)
    /// - Returns: `swift build`에 전달할 인자 문자열 배열
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

    /// 프론트엔드 `dist` 디렉터리의 최종 URL을 해석합니다.
    /// `distOverride`가 있으면 이를 우선 사용하고, 없으면 설정 파일의
    /// `build.frontendDist` 값을 기준 디렉터리와 결합합니다.
    ///
    /// - Parameters:
    ///   - config: Kalsae 앱 설정
    ///   - configURL: `kalsae.json` 설정 파일의 URL
    ///   - cwd: 현재 작업 디렉터리 (명령 실행 위치)
    ///   - distOverride: 명령행 `--dist` 인자로 전달된 재정의 경로 (선택 사항)
    /// - Returns: 해석된 `dist` 디렉터리의 절대 URL
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

    /// 프론트엔드 `dist` 디렉터리의 유효성을 검사합니다.
    /// 디렉터리가 존재하는지, 비어 있지 않은지, `index.html`이 포함되어
    /// 있는지 확인합니다.
    ///
    /// - Parameters:
    ///   - distURL: 검사할 dist 디렉터리 URL
    ///   - allowMissingDist: `true`이면 모든 검사를 건너뜁니다
    ///     (`--allow-missing-dist` 플래그 대응)
    ///   - fm: 파일매니저 인스턴스 (테스트에서 주입 가능)
    /// - Throws: `KSBuildPlanError` — 유효성 검사 실패 시
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

/// `kalsae dev` 명령에 필요한 개발 서버 계획(Dev Plan)을 나타냅니다.
///
/// 설정 파일과 명령행 인자를 종합하여 다음 정보를 결정합니다:
/// - 실행할 dev 명령어 (예: `npm run dev`)
/// - dev 서버가 준비될 때까지 기다릴지 여부
/// - dev 서버의 URL (리치치 프로브 대상)
public struct KSDevPlan: Sendable {
    /// 실행할 개발 서버 명령어 (예: `"npm run dev"`). `nil`이면 명령어를 실행하지 않습니다.
    public var devCommand: String?
    /// dev 서버가 응답할 때까지 기다릴지 여부.
    public var shouldWaitForDevServer: Bool
    /// dev 서버의 URL (연결 가능성 프로브에 사용).
    public var devServerURL: String?

    public init(devCommand: String?, shouldWaitForDevServer: Bool, devServerURL: String?) {
        self.devCommand = devCommand
        self.shouldWaitForDevServer = shouldWaitForDevServer
        self.devServerURL = devServerURL
    }

    /// 설정(config)과 명령행 플래그를 바탕으로 `KSDevPlan`을 생성합니다.
    ///
    /// dev 명령어 실행 여부(`skipDevCommand`), 대기 여부(`noWaitDevServer`),
    /// 서버 URL 재정의(`devServerURLOverride`)를 고려하여 최종 계획을 수립합니다.
    ///
    /// - Parameters:
    ///   - config: Kalsae 앱 설정 (nil 허용 — 설정이 없으면 명령어/URL 없음)
    ///   - skipDevCommand: `true`이면 dev 명령어를 실행하지 않음
    ///   - noWaitDevServer: `true`이면 dev 서버 연결 가능성 프로브를 건너뜀
    ///   - devServerURLOverride: 명령행에서 재정의한 dev 서버 URL (선택 사항)
    /// - Returns: 수립된 `KSDevPlan`
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

    /// 주어진 URL 문자열이 원격 URL(`http://` 또는 `https://`)인지 확인합니다.
    /// 로컬 파일 URL이나 빈 문자열은 `false`를 반환합니다.
    /// - Parameter text: 확인할 URL 문자열
    /// - Returns: http 또는 https 스킴이면 `true`
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

// MARK: - 설정 파일 위치 탐색 (Configuration File Location Discovery)

/// `kalsae.json` 설정 파일의 위치를 탐색합니다.
///
/// 다음 우선순위로 파일을 찾습니다:
/// 1. `cwd/kalsae.json` — 현재 작업 디렉터리에 직접 위치한 경우
/// 2. `cwd/Sources/<*>/Resources/kalsae.json` — SwiftPM 템플릿 구조 내부
///
/// (2)는 `kalsae new`가 `Sources/<NAME>/Resources/`에만 `kalsae.json`을
/// 쓰는 기본 동작과의 호환성을 위해 추가된 fallback입니다. 여러 타겟이
/// 있을 경우 사전 순서로 정렬하여 첫 번째 것을 반환합니다.
public enum KSConfigLocator {
    /// 설정 파일의 표준 이름입니다.
    public static let fileName = "kalsae.json"

    /// 현재 작업 디렉터리에서 `kalsae.json`을 탐색합니다.
    /// - Parameters:
    ///   - cwd: 현재 작업 디렉터리 URL
    ///   - fm: 파일매니저 인스턴스 (테스트에서 주입 가능)
    /// - Returns: 발견된 `kalsae.json`의 URL (없으면 `nil`)
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
