public import Foundation

/// `kalsae.json`을 로드하고 검증한다.
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
        }
    }
}
