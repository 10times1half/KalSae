public import Foundation

#if os(Windows)
    internal import WinSDK
#endif

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
            let docs =
                (try? fm.url(
                    for: .documentDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: false
                ).path)
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

    /// Checks both the lexical candidate path and its symlink-resolved real path.
    /// `path`(절대 파일시스템 경로)가 각 패턴의 `$` 확장 이후,
    /// 최소 하나의 `allow` 글롭과 일치하고 어떤 `deny` 글롭과도
    /// 일치하지 않으면 `true`를 반환한다.
    /// `path` 자체는 **확장하지 않으므로**, 이미 해석된 절대 경로를 넘겨야 한다.
    public func permits(absolutePath path: String, in ctx: ExpansionContext) -> Bool {
        let candidate = Self.normalizeSeparators(path)
        guard matchesPatterns(candidate, in: ctx) else { return false }

        // 존재하는 경로 구간만 realpath/final-path 스타일로 정규화하고, 아직
        // 생성되지 않은 꼬리 경로는 그대로 남긴다. 따라서 읽기/쓰기/생성
        // 모두에서 "허용된 디렉터리 내부처럼 보이지만 symlink를 통해 외부로
        // 탈출하는" 케이스를 best-effort로 차단할 수 있다.
        //
        // Windows: Foundation 의 `resolvingSymlinksInPath()` 는 NTFS junction
        // 과 일부 reparse point 를 불완전하게 해석하므로 `CreateFileW` +
        // `GetFinalPathNameByHandleW` 로 직접 실제 경로를 구한다.
        let realPath = Self.normalizeSeparators(Self.resolveRealPath(path))
        return matchesPatterns(realPath, in: ctx)
    }

    /// 존재하는 경로 구간을 realpath/final-path 로 정규화하고 미존재 꼬리는
    /// 그대로 보존한다. 플랫폼별로 구현이 다르다.
    static func resolveRealPath(_ path: String) -> String {
        #if os(Windows)
            return resolveWindowsFinalPath(path)
        #else
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        #endif
    }

    #if os(Windows)
        /// Windows 전용 final-path 해석.
        ///
        /// 1. 가장 깊은 **존재하는** 부모 디렉터리/파일을 찾는다.
        /// 2. `CreateFileW(FILE_FLAG_BACKUP_SEMANTICS)` 로 핸들을 얻는다
        ///    (디렉터리도 열 수 있도록 BACKUP_SEMANTICS 필수).
        /// 3. `GetFinalPathNameByHandleW(VOLUME_NAME_DOS)` 로 reparse point /
        ///    junction / symlink 가 모두 해석된 normalized DOS path 를 얻는다.
        /// 4. `\\?\` 또는 `\\?\UNC\` prefix 를 제거한다.
        /// 5. 미존재 꼬리 컴포넌트를 다시 append.
        ///
        /// 어떤 단계든 실패하면 Foundation fallback (`resolvingSymlinksInPath`)
        /// 으로 떨어진다.
        static func resolveWindowsFinalPath(_ path: String) -> String {
            let fm = FileManager.default
            let fallback = {
                URL(fileURLWithPath: path)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL.path
            }
            // 1) 가장 깊은 존재하는 prefix 검색. 단, drive root(`C:\`) 까지
            //    올라가버리면 Foundation 의 lexical 정규화와 결과가 갈라져
            //    fake 경로(예: synthetic `/home/u/...`) 매칭이 깨진다. 따라서
            //    leaf 또는 직계 부모가 존재할 때만 Win32 해석을 수행하고,
            //    그렇지 않으면 Foundation fallback 으로 떨어진다.
            var existing = path
            var tail: [String] = []
            if !fm.fileExists(atPath: existing) {
                let parentURL = URL(fileURLWithPath: existing).deletingLastPathComponent()
                let parentPath = parentURL.path
                guard !parentPath.isEmpty,
                    parentPath != existing,
                    fm.fileExists(atPath: parentPath)
                else {
                    return fallback()
                }
                tail.insert(URL(fileURLWithPath: existing).lastPathComponent, at: 0)
                existing = parentPath
            }

            // 2)~3) CreateFileW + GetFinalPathNameByHandleW.
            let resolvedExisting: String? = existing.withCString(encodedAs: UTF16.self) {
                wp -> String? in
                let shareMode = DWORD(
                    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE)
                let handle = CreateFileW(
                    wp,
                    0,  // 메타데이터만 필요 — 접근 권한 0.
                    shareMode,
                    nil,
                    DWORD(OPEN_EXISTING),
                    DWORD(FILE_FLAG_BACKUP_SEMANTICS),
                    nil)
                guard let h = handle, h != INVALID_HANDLE_VALUE else { return nil }
                defer { CloseHandle(h) }

                // VOLUME_NAME_DOS(0) | FILE_NAME_NORMALIZED(0) = 0.
                let flags: DWORD = 0
                let needed = GetFinalPathNameByHandleW(h, nil, 0, flags)
                guard needed > 0 else { return nil }
                var buf = [WCHAR](repeating: 0, count: Int(needed) + 1)
                let written = buf.withUnsafeMutableBufferPointer { bp -> DWORD in
                    GetFinalPathNameByHandleW(h, bp.baseAddress, DWORD(bp.count), flags)
                }
                guard written > 0, Int(written) < buf.count else { return nil }
                return String(decoding: buf.prefix(Int(written)), as: UTF16.self)
            }

            guard var final = resolvedExisting else {
                return fallback()
            }

            // 4) prefix 제거. `\\?\UNC\server\share` → `\\server\share`,
            //    `\\?\C:\dir` → `C:\dir`.
            if final.hasPrefix(#"\\?\UNC\"#) {
                final = #"\\"# + String(final.dropFirst(#"\\?\UNC\"#.count))
            } else if final.hasPrefix(#"\\?\"#) {
                final = String(final.dropFirst(#"\\?\"#.count))
            }

            // 5) 미존재 꼬리 다시 append.
            for component in tail {
                if !final.hasSuffix(#"\"#) {
                    final.append(#"\"#)
                }
                final.append(component)
            }
            return final
        }
    #endif

    // MARK: - 내부 헬퍼

    /// `\`를 `/`로 접어 한쪽 구분자로 작성된 글롭 패턴이
    /// 다른 쪽 구분자로 작성된 경로와도 일치하게 만든다(Windows는 둘 다 허용).
    static func normalizeSeparators(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "/")
    }

    private func matchesPatterns(_ path: String, in ctx: ExpansionContext) -> Bool {
        for pattern in deny {
            let p = Self.expand(pattern, in: ctx)
            if Self.glob(pattern: p, matches: path) { return false }
        }
        for pattern in allow {
            let p = Self.expand(pattern, in: ctx)
            if Self.glob(pattern: p, matches: path) { return true }
        }
        return false
    }

    /// Tauri 호환 글롭 매처.
    ///   * `**` — `/`를 포함한 임의 길이 문자열과 일치.
    ///   * `*`  — `/`를 제외한 임의 길이 문자열과 일치.
    ///   * `?`  — `/`가 아닌 단일 문자와 일치.
    /// `pattern` 안의 다른 정규식 메타문자는 이스케이프된다.
    public static func glob(pattern: String, matches input: String) -> Bool {
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
