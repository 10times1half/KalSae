public import Foundation

extension KSFSScope {
    /// Resolved/expanded form of a path string after `$APP`, `$HOME`,
    /// `$DOCS`, `$TEMP` substitution. Always absolute, NFC-normalised.
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

        /// Default expansion context derived from the running process:
        /// * `$HOME` — `FileManager.default.homeDirectoryForCurrentUser`
        /// * `$DOCS` — user `Documents` directory (falls back to `$HOME/Documents`)
        /// * `$TEMP` — `NSTemporaryDirectory()`
        /// * `$APP`  — `appDirectory` argument (typically the app bundle / install root)
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

    /// Expands `$APP`, `$HOME`, `$DOCS`, `$TEMP` placeholders in `s` using
    /// `ctx`, then returns the result with backslashes folded to forward
    /// slashes for portable matching (the underlying file APIs accept
    /// either on Windows).
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

    /// Returns `true` when `path` (an absolute filesystem path) matches
    /// at least one `allow` glob and no `deny` glob, after `$`-expansion
    /// of each pattern. `path` itself is **not** expanded — supply an
    /// already-resolved absolute path.
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

    // MARK: - Internal helpers

    /// Folds `\` → `/` so glob patterns written with one separator match
    /// paths written with the other (Windows accepts both).
    static func normalizeSeparators(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "/")
    }

    /// Tauri-compatible glob matcher. Supports:
    ///   * `**` — matches any sequence of characters including `/`.
    ///   * `*`  — matches any sequence of non-`/` characters.
    ///   * `?`  — matches a single non-`/` character.
    /// Other regex metacharacters in `pattern` are escaped.
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
        // Case-insensitive on Windows, case-sensitive elsewhere.
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
