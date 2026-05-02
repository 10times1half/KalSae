#if os(Linux)
    internal import CKalsaeGtk
    public import KalsaeCore
    public import Foundation

    /// Linux implementation of `KSClipboardBackend` using GDK4 clipboard.
    /// All operations require the GTK window to be realized (after activate).
    public struct KSLinuxClipboardBackend: KSClipboardBackend, Sendable {
        public init() {}

        // MARK: - KSClipboardBackend

        public func readText() async throws(KSError) -> String? {
            await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
                Task { @MainActor in
                    guard let host = self.primaryHost() else {
                        cont.resume(returning: nil)
                        return
                    }
                    let box = ClipReadBox(cont)
                    let ptr = Unmanaged.passRetained(box).toOpaque()
                    ks_gtk_clipboard_read_text(
                        host.hostPtr,
                        { text, ctx in
                            let b = Unmanaged<ClipReadBox>.fromOpaque(ctx!).takeRetainedValue()
                            b.cont.resume(returning: text.map { String(cString: $0) })
                        }, ptr)
                }
            }
        }

        public func writeText(_ text: String) async throws(KSError) {
            let ok: Bool = await MainActor.run {
                guard let host = primaryHost() else { return false }
                ks_gtk_clipboard_write_text(host.hostPtr, text)
                return true
            }
            if !ok {
                throw KSError(
                    code: .unsupportedPlatform,
                    message: "KSLinuxClipboardBackend: no GTK window available")
            }
        }

        public func readImage() async throws(KSError) -> Data? {
            await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
                Task { @MainActor in
                    guard let host = self.primaryHost() else {
                        cont.resume(returning: nil)
                        return
                    }
                    let box = ClipImageReadBox(cont)
                    let ptr = Unmanaged.passRetained(box).toOpaque()
                    ks_gtk_clipboard_read_png(
                        host.hostPtr,
                        { bytes, len, ctx in
                            let b = Unmanaged<ClipImageReadBox>.fromOpaque(ctx!)
                                .takeRetainedValue()
                            if let bytes, len > 0 {
                                b.cont.resume(returning: Data(bytes: bytes, count: len))
                            } else {
                                b.cont.resume(returning: nil)
                            }
                        }, ptr)
                }
            }
        }

        public func writeImage(_ image: Data) async throws(KSError) {
            let ok: Bool = await MainActor.run {
                guard let host = primaryHost() else { return false }
                return image.withUnsafeBytes { buf in
                    guard let ptr = buf.baseAddress else { return false }
                    return ks_gtk_clipboard_write_png(
                        host.hostPtr,
                        ptr.assumingMemoryBound(to: UInt8.self),
                        buf.count) != 0
                }
            }
            if !ok {
                throw KSError(
                    code: .unsupportedPlatform,
                    message: "KSLinuxClipboardBackend.writeImage: failed (invalid PNG or no window)")
            }
        }

        public func clear() async throws(KSError) {
            let ok: Bool = await MainActor.run {
                guard let host = primaryHost() else { return false }
                ks_gtk_clipboard_clear(host.hostPtr)
                return true
            }
            if !ok {
                throw KSError(
                    code: .unsupportedPlatform,
                    message: "KSLinuxClipboardBackend: no GTK window available")
            }
        }

        public func hasFormat(_ format: String) async -> Bool {
            await MainActor.run {
                guard let host = primaryHost() else { return false }
                switch format.lowercased() {
                case "text":
                    return ks_gtk_clipboard_has_text(host.hostPtr) != 0
                case "image", "image/png":
                    return ks_gtk_clipboard_has_image(host.hostPtr) != 0
                default:
                    return false
                }
            }
        }

        // MARK: - Helpers

        @MainActor
        private func primaryHost() -> GtkWebViewHost? {
            let reg = KSLinuxHandleRegistry.shared
            return reg.allHandles().first.flatMap { reg.entry(for: $0) }?.host
        }
    }

    // MARK: - Continuation boxes

    /// Boxes a `CheckedContinuation` so it can survive the C callback boundary.
    // @unchecked: GTK async callback box \u2014 continuation captured for deferred resumption
    private final class ClipReadBox: @unchecked Sendable {
        let cont: CheckedContinuation<String?, Never>
        init(_ cont: CheckedContinuation<String?, Never>) { self.cont = cont }
    }

    // @unchecked: GTK async callback box \u2014 continuation captured for deferred resumption
    private final class ClipImageReadBox: @unchecked Sendable {
        let cont: CheckedContinuation<Data?, Never>
        init(_ cont: CheckedContinuation<Data?, Never>) { self.cont = cont }
    }
#endif
