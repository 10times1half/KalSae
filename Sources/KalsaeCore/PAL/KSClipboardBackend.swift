public import Foundation

/// System clipboard read/write.
///
/// The protocol is intentionally minimal — formats beyond plain text and
/// raw image bytes are deferred to a later phase. Methods are async so
/// implementations can hop to the UI thread (Win32's `OpenClipboard`,
/// AppKit's `NSPasteboard`, GDK's `gdk_clipboard_*`).
public protocol KSClipboardBackend: Sendable {
    /// Reads UTF-8 plain text. Returns `nil` when the clipboard is empty
    /// or holds a non-text format we don't understand.
    func readText() async throws(KSError) -> String?

    /// Replaces the clipboard contents with `text`.
    func writeText(_ text: String) async throws(KSError)

    /// Reads the clipboard as raw PNG bytes. Returns `nil` when the
    /// clipboard does not hold an image.
    func readImage() async throws(KSError) -> Data?

    /// Replaces the clipboard contents with `image` (PNG-encoded).
    func writeImage(_ image: Data) async throws(KSError)

    /// Clears all clipboard formats.
    func clear() async throws(KSError)

    /// Returns `true` when at least one of the given formats is present.
    /// Format names follow the platform-neutral set: `"text"`, `"image"`,
    /// `"files"`. Unknown formats yield `false`.
    func hasFormat(_ format: String) async -> Bool
}

extension KSClipboardBackend {
    @inline(__always)
    private func _unsupportedThrow(_ op: String) throws(KSError) -> Never {
        throw KSError(code: .unsupportedPlatform,
                      message: "KSClipboardBackend.\(op) is not implemented on this platform.")
    }

    public func readText() async throws(KSError) -> String? { try _unsupportedThrow("readText") }
    public func writeText(_ text: String) async throws(KSError) { try _unsupportedThrow("writeText") }
    public func readImage() async throws(KSError) -> Data? { try _unsupportedThrow("readImage") }
    public func writeImage(_ image: Data) async throws(KSError) { try _unsupportedThrow("writeImage") }
    public func clear() async throws(KSError) { try _unsupportedThrow("clear") }
    public func hasFormat(_ format: String) async -> Bool { false }
}
