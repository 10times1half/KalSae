public import Foundation

/// `KSWebViewOptions.userDataPath` 의 안전 검증기.
///
/// WebView 사용자 데이터 폴더(쿠키, IndexedDB, Service Worker 등)는
/// 무제한 경로 지정이 가능하면 권한 상승 / 민감 데이터 노출 / 재배치를
/// 통한 임의 파일 덮어쓰기 등의 위험이 있다. 본 검증기는 다음을 강제한다:
///
/// 1. `%VAR%` (Windows) 또는 `$VAR` (POSIX) 환경 변수를 확장한다.
/// 2. `..` 등을 포함한 모든 경로 세그먼트를 정규화한다.
/// 3. 심볼릭 링크를 해석하여 실제 대상 위치를 검증한다.
/// 4. 결과 절대경로가 다음 화이트리스트 영역 중 한 곳 안에 위치해야 한다:
///    - 사용자 홈 (`$HOME` / `%USERPROFILE%`)
///    - 시스템 임시 디렉터리 (`NSTemporaryDirectory()`)
///    - Windows: `%LOCALAPPDATA%` / `%APPDATA%` / `%TEMP%`
///
/// 정책 통과 시 정규화된 절대경로 문자열을 반환한다.
public enum KSUserDataPathValidator {
    public struct ValidationFailure: Error, Equatable, Sendable {
        public enum Reason: String, Sendable {
            case empty
            case relative
            case parentTraversal
            case outsideAllowedRoots
        }
        public let reason: Reason
        public let resolvedPath: String?

        public var message: String {
            switch reason {
            case .empty:
                return "userDataPath is empty"
            case .relative:
                return "userDataPath must be absolute (got: \(resolvedPath ?? "<nil>"))"
            case .parentTraversal:
                return "userDataPath must not contain '..' segments (got: \(resolvedPath ?? "<nil>"))"
            case .outsideAllowedRoots:
                return
                    "userDataPath is outside the allowed roots ($HOME / temp / %LOCALAPPDATA%): \(resolvedPath ?? "<nil>")"
            }
        }
    }

    /// 입력 경로를 검증하고 정규화된 절대경로를 반환한다.
    public static func validate(
        _ raw: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        temporaryDirectory: String = NSTemporaryDirectory()
    ) throws(ValidationFailure) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationFailure(reason: .empty, resolvedPath: nil)
        }

        let expanded = expandEnvVars(trimmed, environment: environment)

        // 정규화 전에 `..` 세그먼트를 직접 확인 (정규화가 흡수해버리면
        // 의도치 않은 escape가 가능해진다).
        let segments =
            expanded
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
        if segments.contains(where: { $0 == ".." }) {
            throw ValidationFailure(reason: .parentTraversal, resolvedPath: expanded)
        }

        // 절대경로 검사 (POSIX `/`, Windows 드라이브 `C:\`).
        guard isAbsolute(expanded) else {
            throw ValidationFailure(reason: .relative, resolvedPath: expanded)
        }

        // 정규화 + 심볼릭 링크 해석.
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().path

        // 화이트리스트 루트.
        var roots: [String] = []
        if !homeDirectory.isEmpty { roots.append(homeDirectory) }
        if !temporaryDirectory.isEmpty { roots.append(temporaryDirectory) }
        for key in ["LOCALAPPDATA", "APPDATA", "TEMP", "USERPROFILE"] {
            if let v = environment[key], !v.isEmpty { roots.append(v) }
        }
        for key in ["HOME"] {
            if let v = environment[key], !v.isEmpty { roots.append(v) }
        }

        let normalizedTarget = normalize(resolved)
        for root in roots {
            let normalizedRoot = normalize(root)
            if normalizedRoot.isEmpty { continue }
            if normalizedTarget == normalizedRoot
                || normalizedTarget.hasPrefix(normalizedRoot + "/")
            {
                return resolved
            }
        }
        throw ValidationFailure(reason: .outsideAllowedRoots, resolvedPath: resolved)
    }

    // MARK: - Internals

    /// `%VAR%` (Windows) 와 `$VAR` (POSIX) 환경 변수를 확장한다.
    public static func expandEnvVars(_ input: String, environment: [String: String]) -> String {
        var s = input

        // `%VAR%` 토큰
        while let open = s.firstIndex(of: "%") {
            let after = s.index(after: open)
            guard let close = s[after...].firstIndex(of: "%") else { break }
            let name = String(s[after..<close])
            let replacement = environment[name] ?? ""
            s.replaceSubrange(open...close, with: replacement)
        }

        // `$VAR` 토큰 (영숫자/언더스코어 종료)
        var out: [Character] = []
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "$" {
                let nameStart = s.index(after: i)
                var nameEnd = nameStart
                while nameEnd < s.endIndex {
                    let c = s[nameEnd]
                    if c.isLetter || c.isNumber || c == "_" {
                        nameEnd = s.index(after: nameEnd)
                    } else {
                        break
                    }
                }
                if nameEnd > nameStart {
                    let name = String(s[nameStart..<nameEnd])
                    if let v = environment[name] {
                        out.append(contentsOf: v)
                    }
                    i = nameEnd
                    continue
                }
            }
            out.append(ch)
            i = s.index(after: i)
        }
        return String(out)
    }

    /// POSIX `/...` 또는 Windows `C:\...` / `\\server\...` 형태인지 검사.
    public static func isAbsolute(_ path: String) -> Bool {
        if path.hasPrefix("/") { return true }
        if path.hasPrefix("\\\\") { return true }  // UNC
        // 드라이브 문자 + 콜론 + 구분자: `C:\` 또는 `C:/`
        let chars = Array(path)
        if chars.count >= 3,
            chars[0].isLetter,
            chars[1] == ":",
            chars[2] == "\\" || chars[2] == "/"
        {
            return true
        }
        return false
    }

    /// 비교용 정규화: 슬래시 통일 + 후행 슬래시 제거 + 케이스(Windows에선
    /// 대소문자 무시) 정규화. 대소문자 정책은 항상 lowercase를 채택해
    /// 플랫폼 간 결정성을 유지한다 (POSIX는 case-sensitive지만 사용자가
    /// 경로 표기를 다르게 줘도 동등 비교되도록 단순화).
    private static func normalize(_ path: String) -> String {
        var s = path.replacingOccurrences(of: "\\", with: "/")
        while s.hasSuffix("/") && s.count > 1 {
            s.removeLast()
        }
        return s.lowercased()
    }
}
