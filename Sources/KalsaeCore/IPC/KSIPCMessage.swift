public import Foundation

/// Wire-level envelope exchanged between Swift and JS over the native
/// webview bridge.
///
/// The format deliberately mirrors Tauri's v2 IPC so that TypeScript types
/// generated from registered commands remain ergonomic.
public struct KSIPCMessage: Codable, Sendable, Equatable {
    /// Discriminator selecting how the rest of the envelope is interpreted.
    public enum Kind: String, Codable, Sendable {
        /// JS → Swift: invoke a registered `@KSCommand`.
        case invoke
        /// Swift → JS: response to a previous `invoke`.
        case response
        /// Swift → JS or JS → Swift: fire-and-forget event.
        case event
    }

    /// See `Kind` — selects how `payload`/`isError` are interpreted.
    public var kind: Kind
    /// Correlates `invoke` with its `response`. Required for those kinds,
    /// ignored for `event`.
    public var id: String?
    /// Command name for `invoke`, event name for `event`.
    public var name: String?
    /// JSON-encoded payload. For `invoke`: arguments. For `response`:
    /// either the return value or a `KSError`. For `event`: the payload.
    public var payload: Data?
    /// When `true`, `payload` encodes a `KSError`.
    public var isError: Bool?

    public init(kind: Kind,
                id: String? = nil,
                name: String? = nil,
                payload: Data? = nil,
                isError: Bool? = nil) {
        self.kind = kind
        self.id = id
        self.name = name
        self.payload = payload
        self.isError = isError
    }
}
