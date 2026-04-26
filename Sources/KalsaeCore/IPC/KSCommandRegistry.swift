public import Foundation

/// Thread-safe registry of `@KSCommand`-exposed functions.
///
/// The `@KSCommand` macro (implemented in a later phase) generates a
/// `register(into:)` call that adds a type-erased handler here. At runtime,
/// the IPC pipeline resolves an invoke message to a handler, decodes args,
/// runs the command, and encodes the result (or `KSError`) back.
public actor KSCommandRegistry {
    public typealias Handler = @Sendable (Data) async -> Result<Data, KSError>

    private var handlers: [String: Handler] = [:]
    private var allowlist: Set<String>? = nil

    public init() {}

    /// Sets the command allowlist. When `nil`, every registered command is
    /// callable. When set, only names in this set are callable — any other
    /// invoke returns `KSError.commandNotAllowed`.
    public func setAllowlist(_ names: [String]?) {
        allowlist = names.map(Set.init)
    }

    /// Registers (or replaces) a handler for `name`.
    public func register(_ name: String, handler: @escaping Handler) {
        handlers[name] = handler
    }

    /// Removes a handler.
    public func unregister(_ name: String) {
        handlers.removeValue(forKey: name)
    }

    /// Returns the names of all registered commands.
    public func registered() -> [String] {
        Array(handlers.keys).sorted()
    }

    /// Dispatches an invoke. Returns the serialized payload or a `KSError`
    /// encoded as JSON when the call fails.
    public func dispatch(name: String, args: Data) async -> Result<Data, KSError> {
        if let allowlist, !allowlist.contains(name) {
            return .failure(.commandNotAllowed(name))
        }
        guard let handler = handlers[name] else {
            return .failure(.commandNotFound(name))
        }
        return await handler(args)
    }
}
