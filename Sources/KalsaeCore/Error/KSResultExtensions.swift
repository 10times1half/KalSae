public import Foundation

extension Result where Failure == KSError {
    /// Typed-throws unwrap. `Result.get()` rethrows untyped, which loses the
    /// `throws(KSError)` contract used throughout the PAL surface; this helper
    /// preserves the typed contract.
    ///
    /// Centralised here to avoid duplicate `fileprivate`/`internal` definitions
    /// across `KSMacWindowBackend`, `KSWin32HandleRegistry`, etc.
    @inlinable
    public func unwrap() throws(KSError) -> Success {
        switch self {
        case .success(let v): return v
        case .failure(let e): throw e
        }
    }
}
