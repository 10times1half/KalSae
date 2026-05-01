#if os(Android)
public import KalsaeCore
public import Foundation

/// Android clipboard backend.
///
/// Android clipboard access requires a `Context` and must run on the main
/// thread — both are JVM-side concerns. This backend uses an injection model:
/// the Android host (JNI layer) populates `onReadText`, `onWriteText`, etc.
/// before the app starts. If a handler is absent the method throws
/// `.unsupportedPlatform` so the JS side receives a clear error.
// @unchecked: JNI + main thread binding — actor unsuitable for JVM thread affinity
public final class KSAndroidClipboardBackend: KSClipboardBackend, @unchecked Sendable {
    private let lock = NSLock()

    // MARK: - Injectable handlers (set by JNI host)

    public var onReadText: (() -> String?)? {
        get { lock.withLock { _onReadText } }
        set { lock.withLock { _onReadText = newValue } }
    }
    private var _onReadText: (() -> String?)?

    public var onWriteText: ((String) -> Void)? {
        get { lock.withLock { _onWriteText } }
        set { lock.withLock { _onWriteText = newValue } }
    }
    private var _onWriteText: ((String) -> Void)?

    public var onClear: (() -> Void)? {
        get { lock.withLock { _onClear } }
        set { lock.withLock { _onClear = newValue } }
    }
    private var _onClear: (() -> Void)?

    public var onHasText: (() -> Bool)? {
        get { lock.withLock { _onHasText } }
        set { lock.withLock { _onHasText = newValue } }
    }
    private var _onHasText: (() -> Bool)?

    public init() {}

    // MARK: - KSClipboardBackend

    public func readText() async throws(KSError) -> String? {
        guard let handler = lock.withLock({ _onReadText }) else {
            throw KSError.unsupportedPlatform(
                "Clipboard readText: Android bridge not installed")
        }
        return handler()
    }

    public func writeText(_ text: String) async throws(KSError) {
        guard let handler = lock.withLock({ _onWriteText }) else {
            throw KSError.unsupportedPlatform(
                "Clipboard writeText: Android bridge not installed")
        }
        handler(text)
    }

    /// Android image clipboard access requires Bitmap/JNI. Not available
    /// in this phase — returns `nil` rather than throwing so callers can
    /// treat it as "empty clipboard".
    public func readImage() async throws(KSError) -> Data? { nil }

    /// Image clipboard write requires JNI. No-op until bridge is wired.
    public func writeImage(_ image: Data) async throws(KSError) { _ = image }

    public func clear() async throws(KSError) {
        if let handler = lock.withLock({ _onClear }) {
            handler()
        } else {
            // Fallback: write empty string if clear hook is absent
            try await writeText("")
        }
    }

    public func hasFormat(_ format: String) async -> Bool {
        switch format.lowercased() {
        case "text":
            if let handler = lock.withLock({ _onHasText }) {
                return handler()
            }
            // Conservative: assume present if we can't check
            return false
        default:
            return false
        }
    }
}
#endif
