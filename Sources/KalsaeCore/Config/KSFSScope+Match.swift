public import Foundation

extension KSFSScope {
    /// `$APP`, `$HOME`, `$DOCS`, `$TEMP` 치환 후의 경로 문자열 확장 결과.
    /// 항상 절대 경로이며 NFC 정규화 상태를 유지한다.
    public struct ExpansionContext: Sendable, Equatable {
        public var app: String
        public var home: String
        public var docs: String
        public var temp: String

        public init(app: String, home: String, docs: String, temp: String) {
            self.app = app
            self.home = home
            self.docs = docs
            self.temp = temp
        }

        /// 실행 중인 프로세스에서 파생되는 기본 확장 컨텍스트.
        /// * `$HOME` — `FileManager.default.homeDirectoryForCurrentUser`
        /// * `$DOCS` — 사용자 `Documents` 디렉터리 (`$HOME/Documents`로 폴백)
        /// * `$TEMP` — `NSTemporaryDirectory()`
        /// * `$APP`  — `appDirectory` 인자(보통 앱 번들/설치 루트)
        public static func current(appDirectory: URL) -> ExpansionContext {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser.path
            let docs = (try? fm.url(
                for: .documentDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false).path)
                ?? (home + "/Documents")
            let temp = NSTemporaryDirectory()
            return .init(app: appDirectory.path, home: home, docs: docs, temp: temp)
        }
    }

    /// `ctx`를 사용해 `s` 안의 `$APP`, `$HOME`, `$DOCS`, `$TEMP`
    /// 플레이스홀더를 확장한 뒤, 이식성 있는 매칭을 위해 역슬래시를
    /// 슬래시로 접은 결과를 반환한다(Windows의 기본 파일 API는 둘 다 허용).
    public static func expand(_ s: String, in ctx: ExpansionContext) -> String {
        var out = s
        let pairs: [(String, String)] = [
            ("$APP", ctx.app),
            ("$HOME", ctx.home),
            ("$DOCS", ctx.docs),
            ("$TEMP", ctx.temp),
        ]
        for (k, v) in pairs {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return normalizeSeparators(out)
    }

    /// `path`(절대 파일시스템 경로)가 각 패턴의 `$` 확장 이후,
    /// 최소 하나의 `allow` 글롭과 일치하고 어떤 `deny` 글롭과도
    /// 일치하지 않으면 `true`를 반환한다.
    /// `path` 자체는 **확장하지 않으므로**, 이미 해석된 절대 경로를 넘겨야 한다.
    public func permits(absolutePath path: String, in ctx: ExpansionContext) -> Bool {
        let needle = Self.normalizeSeparators(path)
        for pattern in deny {
            let p = Self.expand(pattern, in: ctx)
            if Self.glob(pattern: p, matches: needle) { return false }
        }
        for pattern in allow {
            let p = Self.expand(pattern, in: ctx)
            if Self.glob(pattern: p, matches: needle) { return true }
        }
        return false
    }

    // MARK: - 내부 헬퍼

    /// `\`를 `/`로 접어 한쪽 구분자로 작성된 글롭 패턴이
    /// 다른 쪽 구분자로 작성된 경로와도 일치하게 만든다(Windows는 둘 다 허용).
    static func normalizeSeparators(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "/")
    }

    /// Tauri 호환 글롭 매처.
    ///   * `**` — `/`를 포함한 임의 길이 문자열과 일치.
    ///   * `*`  — `/`를 제외한 임의 길이 문자열과 일치.
    ///   * `?`  — `/`가 아닌 단일 문자와 일치.
    /// `pattern` 안의 다른 정규식 메타문자는 이스케이프된다.
    static func glob(pattern: String, matches input: String) -> Bool {
        var rx = "^"
        var i = pattern.startIndex
        while i < pattern.endIndex {
            let c = pattern[i]
            switch c {
            case "*":
                let next = pattern.index(after: i)
                if next < pattern.endIndex, pattern[next] == "*" {
                    rx += ".*"
                    i = pattern.index(after: next)
                    continue
                }
                rx += "[^/]*"
            case "?":
                rx += "[^/]"
            case ".", "(", ")", "+", "|", "^", "$", "{", "}", "[", "]", "\\":
                rx += "\\"
                rx.append(c)
            default:
                rx.append(c)
            }
            i = pattern.index(after: i)
        }
        rx += "$"
        // Windows에서는 대소문자를 구분하지 않고, 그 외 플랫폼에서는 구분한다.
        #if os(Windows)
        let opts: NSRegularExpression.Options = [.caseInsensitive]
        #else
        let opts: NSRegularExpression.Options = []
        #endif
        guard let regex = try? NSRegularExpression(pattern: rx, options: opts) else {
            return false
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.firstMatch(in: input, options: [], range: range) != nil
    }
}
