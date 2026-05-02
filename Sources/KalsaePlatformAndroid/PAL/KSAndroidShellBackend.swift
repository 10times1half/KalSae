#if os(Android)
    public import KalsaeCore
    public import Foundation

    /// Android shell backend.
    ///
    /// Opening URLs on Android requires `Intent.ACTION_VIEW` which is a JVM call.
    /// The handler injection model lets the Android host (JNI layer) supply a
    /// closure before the app starts without importing JNI at Swift compile time.
    // @unchecked: JNI + Intent dispatch — actor unsuitable for Intent-based API
    public final class KSAndroidShellBackend: KSShellBackend, @unchecked Sendable {
        private let lock = NSLock()

        // MARK: - Injectable handler (set by JNI host)

        /// Called by `openExternal`. The handler receives the URL string and
        /// returns `true` if it was accepted, `false` if the intent failed.
        public var onOpenExternal: ((URL) -> Bool)? {
            get { lock.withLock { _onOpenExternal } }
            set { lock.withLock { _onOpenExternal = newValue } }
        }
        private var _onOpenExternal: ((URL) -> Bool)?

        public init() {}

        // MARK: - KSShellBackend

        public func openExternal(_ url: URL) async throws(KSError) {
            guard let handler = lock.withLock({ _onOpenExternal }) else {
                throw KSError.unsupportedPlatform(
                    "Shell openExternal: Android bridge not installed")
            }
            let accepted = handler(url)
            if !accepted {
                throw KSError(
                    code: .shellInvocationFailed,
                    message: "Android: no Activity found for URL '\(url.absoluteString)'")
            }
        }

        /// Revealing files in a folder is not a standard Android paradigm.
        /// Delegates to `openExternal` as a best-effort.
        public func showItemInFolder(_ url: URL) async throws(KSError) {
            try await openExternal(url)
        }

        /// Trash / Recycle Bin does not exist on Android.
        public func moveToTrash(_ url: URL) async throws(KSError) {
            _ = url
            throw KSError.unsupportedPlatform("moveToTrash is not supported on Android")
        }
    }
#endif
