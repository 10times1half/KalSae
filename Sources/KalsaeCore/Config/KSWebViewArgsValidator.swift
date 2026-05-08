internal import Foundation

/// `KSWebViewWindowsOptions.additionalBrowserArguments` 의 안전 검증기.
///
/// WebView2 / Chromium 명령줄 인자는 보안 모델을 우회하는 위험 옵션이 다수
/// 존재한다 (`--remote-debugging-port`, `--disable-web-security`,
/// `--no-sandbox` 등). 본 검증기는 부팅 시 토큰 단위로 분해하여 블랙리스트
/// 매칭되는 인자를 거부한다.
///
/// 정책:
/// - 블랙리스트 매칭은 케이스 무시 + `=` 또는 공백으로 끝나는 prefix 매칭이다.
///   예) `--no-sandbox` 토큰은 `--no-sandbox`로 시작하는 모든 토큰을 매칭한다.
/// - 토크나이저는 큰따옴표 안의 공백을 보존한다 (Chromium 자체 파서와 호환).
/// - 빈 문자열 / 공백만 있는 문자열은 그대로 통과한다.
public enum KSWebViewArgsValidator {
    /// 보안을 무력화하는 인자 prefix 목록.
    /// 모두 소문자 정규화로 비교한다.
    public static let blockedPrefixes: [String] = [
        "--remote-debugging-port",
        "--remote-debugging-pipe",
        "--remote-allow-origins",
        "--disable-web-security",
        "--no-sandbox",
        "--disable-site-isolation-trials",
        "--disable-site-isolation-for-policy",
        "--allow-running-insecure-content",
        "--user-data-dir",
        "--disable-features=isolateorigins",
        "--unsafely-treat-insecure-origin-as-secure",
    ]

    /// 거절 사유와 위반 토큰을 함께 담는 결과 타입.
    public struct ValidationFailure: Error, Equatable, Sendable {
        public let token: String
        public let matchedPrefix: String
        public var message: String {
            "Disallowed Chromium argument '\(token)' (matches '\(matchedPrefix)')"
        }
    }

    /// `args`를 토큰화한 뒤 블랙리스트와 비교한다.
    /// 위반이 없으면 정규화된 토큰 목록을 반환한다.
    public static func validate(_ args: String) throws(ValidationFailure) -> [String] {
        let tokens = tokenize(args)
        for token in tokens {
            if let matched = blockedPrefix(for: token) {
                throw ValidationFailure(token: token, matchedPrefix: matched)
            }
        }
        return tokens
    }

    /// 한 토큰이 어떤 블랙리스트 prefix와 매칭되는지 검사한다.
    /// 매칭되지 않으면 `nil`.
    public static func blockedPrefix(for token: String) -> String? {
        let lower = token.lowercased()
        for prefix in blockedPrefixes {
            if lower == prefix || lower.hasPrefix(prefix + "=") || lower.hasPrefix(prefix + " ") {
                return prefix
            }
        }
        return nil
    }

    /// 인자 문자열을 토큰 목록으로 분해한다.
    /// 큰따옴표 안의 공백은 보존하고, 따옴표는 결과 토큰에서 제거된다.
    public static func tokenize(_ args: String) -> [String] {
        var tokens: [String] = []
        var current: [Character] = []
        var inQuotes = false
        for ch in args {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if !inQuotes, ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(String(current))
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            current.append(ch)
        }
        if !current.isEmpty { tokens.append(String(current)) }
        return tokens
    }

    /// `mediaAutoplay` preference를 Chromium `--autoplay-policy=` 토큰으로 매핑한다.
    /// `nil`이면 빈 문자열 (사용자 인자에 영향 없음).
    public static func autoplayPolicyArgument(for policy: KSWebViewMediaAutoplay?) -> String {
        guard let policy else { return "" }
        switch policy {
        case .never:
            return "--autoplay-policy=document-user-activation-required"
        case .userGesture:
            return "--autoplay-policy=user-gesture-required"
        case .always:
            return "--autoplay-policy=no-user-gesture-required"
        }
    }

    /// 사용자가 지정한 `additionalBrowserArguments` 뒤에 `mediaAutoplay`에서
    /// 합성된 인자를 덧붙여 한 문자열로 합친 뒤 검증한다.
    /// 사용자 자신의 `--autoplay-policy=...` 설정이 있으면 합성을 건너뛰어
    /// 사용자 의도를 우선한다.
    public static func compose(
        userArguments: String?,
        mediaAutoplay: KSWebViewMediaAutoplay?
    ) throws(ValidationFailure) -> String {
        let user = userArguments ?? ""
        let autoplay = autoplayPolicyArgument(for: mediaAutoplay)
        let synthesized: String
        if autoplay.isEmpty {
            synthesized = user
        } else if tokenize(user).contains(where: { $0.lowercased().hasPrefix("--autoplay-policy=") }) {
            // 사용자가 직접 정책을 지정한 경우 합성하지 않는다.
            synthesized = user
        } else if user.isEmpty {
            synthesized = autoplay
        } else {
            synthesized = user + " " + autoplay
        }
        _ = try validate(synthesized)
        return synthesized
    }
}
