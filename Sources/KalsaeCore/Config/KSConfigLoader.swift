/// `kalsae.json`을 로드하고 검증한다.
public import Foundation

public enum KSConfigLoader {
    /// 주어진 URL에서 설정을 로드한다.
    public static func load(from url: URL) throws(KSError) -> KSConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw KSError.configNotFound(url.path)
        }
        return try decode(data)
    }

    /// `projectRoot` 내부의 `kalsae.json`에서 설정을 로드한다.
    public static func load(projectRoot: URL) throws(KSError) -> KSConfig {
        let url = projectRoot.appendingPathComponent("kalsae.json")
        return try load(from: url)
    }

    /// 원시 JSON 바이트를 디코딩한다.
    public static func decode(_ data: Data) throws(KSError) -> KSConfig {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        do {
            let config = try decoder.decode(KSConfig.self, from: data)
            try validate(config)
            return config
        } catch let error as KSError {
            // 혼합 throw 사이트 (JSONDecoder + validate(KSError)) — AGENTS §4 참조
            throw error
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw KSError.configInvalid(
                "missing key '\(key.stringValue)' at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw KSError.configInvalid(
                "type mismatch at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)")
        } catch let DecodingError.valueNotFound(_, ctx) {
            throw KSError.configInvalid(
                "value missing at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.dataCorrupted(ctx) {
            throw KSError.configInvalid("corrupted JSON: \(ctx.debugDescription)")
        } catch {
            throw KSError.configInvalid(String(describing: error))
        }
    }

    /// Codable이 강제하는 것 이상의 의미론적 검증.
    public static func validate(_ config: KSConfig) throws(KSError) {
        guard !config.app.name.isEmpty else {
            throw KSError.configInvalid("app.name must not be empty")
        }
        guard !config.app.identifier.isEmpty else {
            throw KSError.configInvalid("app.identifier must not be empty")
        }
        guard !config.windows.isEmpty else {
            throw KSError.configInvalid("at least one window must be declared")
        }
        var seen: Set<String> = []
        for w in config.windows {
            guard !w.label.isEmpty else {
                throw KSError.configInvalid("window.label must not be empty")
            }
            guard seen.insert(w.label).inserted else {
                throw KSError.configInvalid("duplicate window label '\(w.label)'")
            }
            guard w.width > 0, w.height > 0 else {
                throw KSError.configInvalid(
                    "window '\(w.label)' has non-positive dimensions")
            }
            // `webview.platform.windows.additionalBrowserArguments` 의
            // 위험 토큰 차단. 토크나이저는 결정적이므로 config-load 시점에
            // 즉시 거절해 부팅 실패를 조기에 노출한다.
            if let raw = w.webview?.platform?.windows?.additionalBrowserArguments,
                !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                do {
                    _ = try KSWebViewArgsValidator.validate(raw)
                } catch {
                    throw KSError.configInvalid(
                        "window '\(w.label)' webview.platform.windows.additionalBrowserArguments: \(error.message)")
                }
            }
            // `webview.userDataPath` 의 안전 검증. 모든 OS에서 동일 정책을
            // 적용해 `..` 트래버설 / 시스템 경로 침투를 차단한다.
            if let raw = w.webview?.userDataPath,
                !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                do {
                    _ = try KSUserDataPathValidator.validate(raw)
                } catch {
                    throw KSError.configInvalid(
                        "window '\(w.label)' webview.userDataPath: \(error.message)")
                }
            }
        }
        try validateUserScripts(config.security.userScripts)
    }

    /// `security.userScripts`의 의미론적 검증.
    /// - `allowOrigins`가 비어 있으면 `scripts`도 비어 있어야 한다(default-deny).
    /// - 각 스크립트는 `source`/`path` 중 정확히 하나만 지정해야 한다.
    /// - `path`는 `..` 디렉터리 탈출을 포함하지 않아야 한다.
    /// - 각 스크립트의 `origins` 항목은 `allowOrigins`의 부분집합이어야 한다.
    private static func validateUserScripts(_ scope: KSUserScriptsScope) throws(KSError) {
        if scope.allowOrigins.isEmpty && !scope.scripts.isEmpty {
            throw KSError.configInvalid(
                "security.userScripts.scripts is non-empty but security.userScripts.allowOrigins is empty (default-deny)")
        }
        var seenIDs: Set<String> = []
        for (idx, s) in scope.scripts.enumerated() {
            let tag = s.id.isEmpty ? "#\(idx)" : "'\(s.id)'"
            if !s.id.isEmpty {
                guard seenIDs.insert(s.id).inserted else {
                    throw KSError.configInvalid(
                        "security.userScripts.scripts[\(idx)]: duplicate id '\(s.id)'")
                }
            }
            let hasSource = (s.source?.isEmpty == false)
            let hasPath = (s.path?.isEmpty == false)
            if hasSource == hasPath {
                throw KSError.configInvalid(
                    "security.userScripts.scripts[\(idx)] \(tag): exactly one of 'source' or 'path' must be set")
            }
            if let p = s.path, hasPath {
                if p.contains("..") || p.hasPrefix("/") || p.hasPrefix("\\") {
                    throw KSError.configInvalid(
                        "security.userScripts.scripts[\(idx)] \(tag): path must be a relative resourceRoot path without '..'")
                }
            }
            if s.origins.isEmpty {
                throw KSError.configInvalid(
                    "security.userScripts.scripts[\(idx)] \(tag): 'origins' must not be empty")
            }
            for o in s.origins {
                if !scope.permits(originPattern: o) {
                    throw KSError.configInvalid(
                        "security.userScripts.scripts[\(idx)] \(tag): origin '\(o)' is not in security.userScripts.allowOrigins")
                }
            }
        }
    }
}
