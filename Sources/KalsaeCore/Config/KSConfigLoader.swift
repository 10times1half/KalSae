public import Foundation

/// Loads and validates `kalsae.json`.
public enum KSConfigLoader {
    /// Loads the config from the given URL.
    public static func load(from url: URL) throws(KSError) -> KSConfig {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw KSError.configNotFound(url.path)
        }
        return try decode(data)
    }

    /// Loads the config from `kalsae.json` inside `projectRoot`.
    public static func load(projectRoot: URL) throws(KSError) -> KSConfig {
        let url = projectRoot.appendingPathComponent("kalsae.json")
        return try load(from: url)
    }

    /// Decodes raw JSON bytes.
    public static func decode(_ data: Data) throws(KSError) -> KSConfig {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        do {
            let config = try decoder.decode(KSConfig.self, from: data)
            try validate(config)
            return config
        } catch let error as KSError {
            // `validate(_:)`가 던진 KSError는 코드/페이로드 보존을 위해 그대로 전달.
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

    /// Semantic validation beyond what Codable enforces.
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
