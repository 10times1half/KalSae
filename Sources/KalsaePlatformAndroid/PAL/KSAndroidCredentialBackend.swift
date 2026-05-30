#if os(Android)
    public import KalsaeCore
    public import Foundation

    /// Android secure credential backend.
    ///
    /// Storage itself is implemented by the Kotlin host (for example
    /// AndroidKeyStore + EncryptedSharedPreferences). Swift forwards requests
    /// through registered JNI hooks and awaits JSON responses via
    /// `KSAndroidJNIRegistry`.
    public struct KSAndroidCredentialBackend: KSCredentialBackend, Sendable {
        public init() {}

        public func set(_ key: KSCredentialKey, secret: Data) async throws(KSError) {
            struct Req: Encodable {
                let service: String
                let account: String
                let secretBase64: String
            }
            let req = Req(
                service: key.service,
                account: key.account,
                secretBase64: secret.base64EncodedString())

            let _: Empty = try await Self.call(
                request: req,
                hook: { KSAndroidJNIBridge.shared.credentialSet },
                missingHookMessage: "KSAndroidCredentialBackend.set: Kotlin credential hook not installed",
                decode: Self.decodeEmpty)
        }

        public func get(_ key: KSCredentialKey) async throws(KSError) -> Data? {
            struct Req: Encodable {
                let service: String
                let account: String
            }
            struct Payload: Decodable {
                let secretBase64: String?
            }

            let req = Req(service: key.service, account: key.account)
            let payload: Payload = try await Self.call(
                request: req,
                hook: { KSAndroidJNIBridge.shared.credentialGet },
                missingHookMessage: "KSAndroidCredentialBackend.get: Kotlin credential hook not installed",
                decode: Self.decodePayload)

            guard let b64 = payload.secretBase64 else { return nil }
            guard let data = Data(base64Encoded: b64) else {
                throw KSError(
                    code: .ioFailed,
                    message: "Android credential get returned invalid base64 payload")
            }
            return data
        }

        public func delete(_ key: KSCredentialKey) async throws(KSError) {
            struct Req: Encodable {
                let service: String
                let account: String
            }
            let req = Req(service: key.service, account: key.account)

            let _: Empty = try await Self.call(
                request: req,
                hook: { KSAndroidJNIBridge.shared.credentialDelete },
                missingHookMessage: "KSAndroidCredentialBackend.delete: Kotlin credential hook not installed",
                decode: Self.decodeEmpty)
        }

        public func list(service: String) async throws(KSError) -> [KSCredentialKey] {
            struct Req: Encodable {
                let service: String
            }
            struct Payload: Decodable {
                let accounts: [String]?
            }

            let payload: Payload = try await Self.call(
                request: Req(service: service),
                hook: { KSAndroidJNIBridge.shared.credentialList },
                missingHookMessage: "KSAndroidCredentialBackend.list: Kotlin credential hook not installed",
                decode: Self.decodePayload)

            return (payload.accounts ?? []).map {
                KSCredentialKey(service: service, account: $0)
            }
        }
    }

    extension KSAndroidCredentialBackend {
        private struct Envelope<Payload: Decodable>: Decodable {
            let ok: Bool
            let error: String?
            let payload: Payload?

            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
                error = try c.decodeIfPresent(String.self, forKey: .error)

                if let p = try c.decodeIfPresent(Payload.self, forKey: .payload) {
                    payload = p
                } else if let p = try c.decodeIfPresent(Payload.self, forKey: .data) {
                    payload = p
                } else {
                    payload = nil
                }
            }

            private enum CodingKeys: String, CodingKey {
                case ok
                case error
                case payload
                case data
            }
        }

        private struct Empty: Codable, Sendable {}

        private static func call<Request: Encodable, Response>(
            request: Request,
            hook: () -> ((Int32, UnsafePointer<CChar>) -> Void)?,
            missingHookMessage: String,
            decode: @Sendable @escaping (String) throws(KSError) -> Response
        ) async throws(KSError) -> Response {
            guard let fn = hook() else {
                throw KSError.unsupportedPlatform(missingHookMessage)
            }

            let jsonData: Data
            do {
                jsonData = try JSONEncoder().encode(request)
            } catch {
                throw KSError(code: .ioFailed, message: "Android credential request encoding failed")
            }
            guard let json = String(data: jsonData, encoding: .utf8) else {
                throw KSError(code: .ioFailed, message: "Android credential request is not valid UTF-8")
            }

            return try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<Response, Error>) in
                let id = KSAndroidJNIRegistry.shared.register { raw in
                    do {
                        cont.resume(returning: try decode(raw))
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                json.withCString { fn(id, $0) }
            } as Response
        }

        private static func decodeEmpty(_ json: String) throws(KSError) -> Empty {
            _ = try decodeEnvelope(json)
            return Empty()
        }

        private static func decodePayload<T: Decodable>(_ json: String) throws(KSError) -> T {
            let env: Envelope<T> = try decodeEnvelope(json)
            guard let payload = env.payload else {
                throw KSError(
                    code: .ioFailed,
                    message: "Android credential response missing payload")
            }
            return payload
        }

        private static func decodeEnvelope<T: Decodable>(_ json: String) throws(KSError) -> Envelope<T> {
            guard let data = json.data(using: .utf8) else {
                throw KSError(code: .ioFailed, message: "Android credential response is not UTF-8")
            }
            let env: Envelope<T>
            do {
                env = try JSONDecoder().decode(Envelope<T>.self, from: data)
            } catch {
                throw KSError(code: .ioFailed, message: "Android credential response decode failed")
            }
            guard env.ok else {
                throw KSError(
                    code: .ioFailed,
                    message: env.error ?? "Android credential operation failed")
            }
            return env
        }
    }
#endif