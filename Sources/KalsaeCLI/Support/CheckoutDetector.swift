public import Foundation

/// `kalsae` 자체 실행 파일이 Kalsae 소스 체크아웃의 `.build/<triple>/{debug|release}/`
/// 디렉터리 안에 위치하는지 감지해, 그 워크스페이스 루트를 돌려준다.
///
/// `kalsae new` 가 `--kalsae-path` 인자 없이 호출됐을 때 자동으로 로컬 path
/// 의존성으로 폴백할지 결정하는 데 사용한다. GitHub 에 아직 게시되지 않은
/// 패치(예: 핫픽스 작업 중인 KalsaeCore) 도 새 프로젝트에 즉시 반영되도록
/// 해, `from: "X.Y.Z"` 의존성이 GitHub 의 옛 태그를 끌어와 발생하는 회귀를
/// 방지한다.
public enum KSKalsaeCheckoutDetector {
    /// 실행 중인 `kalsae` 실행파일의 절대 경로를 추정한다.
    /// `Bundle.main.executableURL` → `CommandLine.arguments[0]` 순서로 시도.
    public static func currentExecutableURL() -> URL? {
        if let url = Bundle.main.executableURL {
            return url.standardizedFileURL
        }
        guard let arg0 = CommandLine.arguments.first, !arg0.isEmpty else {
            return nil
        }
        let url = URL(
            fileURLWithPath: arg0,
            relativeTo: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath))
        return url.standardizedFileURL
    }

    /// `executableURL` 가 `<root>/.build/.../kalsae[.exe]` 형태이고
    /// `<root>/Package.swift` + `<root>/Sources/Kalsae/Kalsae.swift` 가 존재하면
    /// `<root>` 를 반환. 그 외에는 nil.
    ///
    /// 환경변수 `KALSAE_DISABLE_AUTODETECT_PATH=1` 이 설정되면 항상 nil.
    public static func find(
        executableURL: URL? = currentExecutableURL(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fm: FileManager = .default
    ) -> URL? {
        if environment["KALSAE_DISABLE_AUTODETECT_PATH"] == "1" {
            return nil
        }
        guard let exe = executableURL else { return nil }
        let exePath = exe.standardizedFileURL.path

        for candidate in ancestors(of: exe) {
            let buildDir = candidate.appendingPathComponent(".build")
            let pkgFile = candidate.appendingPathComponent("Package.swift")
            let kalsaeMarker = candidate
                .appendingPathComponent("Sources")
                .appendingPathComponent("Kalsae")
                .appendingPathComponent("Kalsae.swift")
            if fm.fileExists(atPath: buildDir.path),
                fm.fileExists(atPath: pkgFile.path),
                fm.fileExists(atPath: kalsaeMarker.path),
                exePath.hasPrefix(buildDir.standardizedFileURL.path)
            {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    /// `url` 의 모든 ancestor 디렉터리(자기 자신 제외)를 root 까지 리턴.
    private static func ancestors(of url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.deletingLastPathComponent().standardizedFileURL
        while true {
            result.append(current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        return result
    }
}
