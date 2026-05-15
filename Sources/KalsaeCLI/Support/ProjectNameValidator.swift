public import Foundation

/// 프로젝트 식별자(이름)와 경로에 대한 비-ASCII 차단 검증기.
///
/// 배경: Windows 의 SwiftPM 은 임시 빌드 산출물(`<pkg>-output.json`) 경로를
/// 만들 때 Unicode NFC/NFD 정규화 처리에서 깨져, 한글/CJK/악센트 등 비-ASCII
/// 문자가 패키지 이름이나 경로 컴포넌트에 포함되면 빌드가 모호한
/// `'<pkg>-output.json' doesn't exist in file system` 에러로 실패한다.
/// 이 검증기는 호스트 OS 와 무관하게 동일한 규칙을 강제해 cross-platform
/// 이식성을 보장한다 (한글로 만든 프로젝트가 Windows 사용자에게 공유될
/// 때 깨지지 않도록).
///
/// 허용되는 프로젝트 이름:
///   - 첫 글자는 ASCII letter (`a-z`, `A-Z`)
///   - 이후 ASCII letter / digit / `-` / `_` 만
///
/// 허용되는 경로:
///   - 경로 문자열 전체에 비-ASCII unicode scalar 가 없어야 함
///   - 드라이브 문자(`C:`) / 슬래시 / 백슬래시는 모두 ASCII 이므로 자연스럽게 통과
public enum KSProjectNameValidator {

    /// 검증 실패 시 던져지는 에러. `description` 에 사용자 노출 메시지가 들어있다.
    public struct ValidationFailure: Error, CustomStringConvertible {
        public let description: String
        public init(_ description: String) { self.description = description }
    }

    /// 문자열에 비-ASCII unicode scalar 가 포함돼 있는지 검사.
    public static func containsNonASCII(_ s: String) -> Bool {
        s.unicodeScalars.contains { !$0.isASCII }
    }

    /// 프로젝트 이름 검증. ASCII letter 로 시작 + ASCII letter/digit/`-`/`_` 만 허용.
    public static func validateName(_ name: String) throws {
        if name.isEmpty {
            throw ValidationFailure(
                "Project name is empty. "
                    + "Use letters, digits, '-' or '_' (ASCII only), starting with a letter. "
                    + "Try: kalsae new my-app")
        }
        if containsNonASCII(name) {
            throw ValidationFailure(
                "Project name '\(name)' contains non-ASCII characters. "
                    + "Only ASCII letters, digits, '-' and '_' are allowed (must start with a letter). "
                    + "Reason: SwiftPM on Windows fails to find its temporary "
                    + "'<pkg>-output.json' when the package name contains non-ASCII "
                    + "characters (Unicode normalization bug). Kalsae enforces this rule "
                    + "on all platforms to keep projects portable. "
                    + "Try: kalsae new my-app")
        }
        guard let first = name.first, isASCIILetter(first) else {
            throw ValidationFailure(
                "Project name '\(name)' must start with an ASCII letter (a-z, A-Z). "
                    + "Try: kalsae new my-app")
        }
        for ch in name {
            if isASCIILetter(ch) || isASCIIDigit(ch) || ch == "-" || ch == "_" { continue }
            throw ValidationFailure(
                "Project name '\(name)' contains the invalid character '\(ch)'. "
                    + "Only ASCII letters, digits, '-' and '_' are allowed. "
                    + "Try: kalsae new my-app")
        }
    }

    /// 경로 검증. 경로 문자열 전체에 비-ASCII 문자가 없어야 한다.
    /// - Parameters:
    ///   - url: 검사할 경로 (파일 또는 디렉터리).
    ///   - role: 에러 메시지에 들어갈 사람-친화 라벨
    ///     (예: `"current working directory"`, `"--dir target"`).
    public static func validatePath(_ url: URL, role: String) throws {
        let path = url.path
        if containsNonASCII(path) {
            throw ValidationFailure(
                "The \(role) contains non-ASCII characters: \(path). "
                    + "SwiftPM on Windows fails to locate its temporary "
                    + "'<pkg>-output.json' when any path component contains non-ASCII "
                    + "characters (Unicode normalization bug). Kalsae enforces this "
                    + "on all platforms to keep projects portable. "
                    + "Move the project to an ASCII-only path and retry.")
        }
    }

    // MARK: - private helpers

    private static func isASCIILetter(_ ch: Character) -> Bool {
        guard let v = ch.asciiValue else { return false }
        return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
    }

    private static func isASCIIDigit(_ ch: Character) -> Bool {
        guard let v = ch.asciiValue else { return false }
        return v >= 0x30 && v <= 0x39
    }
}
