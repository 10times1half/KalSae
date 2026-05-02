#if os(iOS)
    public import KalsaeCore

    public struct KSiOSAutostartBackend: KSAutostartBackend, Sendable {
        public init() {}

        public func enable() throws(KSError) {
            throw KSError.unsupportedPlatform("Autostart is not available on iOS")
        }

        public func disable() throws(KSError) {
            throw KSError.unsupportedPlatform("Autostart is not available on iOS")
        }

        public func isEnabled() -> Bool {
            false
        }
    }
#endif
