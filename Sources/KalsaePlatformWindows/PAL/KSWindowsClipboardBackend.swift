#if os(Windows)
internal import WinSDK
public import KalsaeCore
public import Foundation

/// Win32 implementation of `KSClipboardBackend`.
///
/// Image read/write converts between PNG and `CF_DIB` via WIC; see
/// `KSWindowsClipboardBackend+Image.swift`.
public struct KSWindowsClipboardBackend: KSClipboardBackend, Sendable {
    public init() {}

    // MARK: - Text

    public func readText() async throws(KSError) -> String? {
        let result: Result<String?, KSError> = await MainActor.run {
            guard OpenClipboard(nil) else {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "OpenClipboard failed (\(GetLastError()))"))
            }
            defer { _ = CloseClipboard() }

            let handle = GetClipboardData(UINT(CF_UNICODETEXT))
            guard let handle else { return .success(nil) }

            // HGLOBAL → 와이드 문자열
            let raw = GlobalLock(handle)
            guard let raw else { return .success(nil) }
            defer { _ = GlobalUnlock(handle) }

            let wptr = raw.assumingMemoryBound(to: UInt16.self)
            return .success(UnsafePointer(wptr).toString())
        }
        return try result.unwrap()
    }

    public func writeText(_ text: String) async throws(KSError) {
        let result: Result<Void, KSError> = await MainActor.run {
            guard OpenClipboard(nil) else {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "OpenClipboard failed (\(GetLastError()))"))
            }
            defer { _ = CloseClipboard() }

            _ = EmptyClipboard()

            // 와이드 문자 페이로드를 담은 이동 가능한 전역 메모리를 할당한다.
            var utf16 = Array(text.utf16)
            utf16.append(0)
            let bytes = utf16.count * MemoryLayout<UInt16>.size
            guard let h = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(bytes)) else {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "GlobalAlloc(\(bytes)) failed (\(GetLastError()))"))
            }
            let dst = GlobalLock(h)
            if let dst {
                utf16.withUnsafeBufferPointer { buf in
                    if let base = buf.baseAddress {
                        memcpy(dst, base, bytes)
                    }
                }
                _ = GlobalUnlock(h)
            }
            if SetClipboardData(UINT(CF_UNICODETEXT), h) == nil {
                _ = GlobalFree(h)
                return .failure(KSError(
                    code: .ioFailed,
                    message: "SetClipboardData failed (\(GetLastError()))"))
            }
            // 성공 시 클립보드로 소유권이 이전된다.
            return .success(())
        }
        try result.unwrap()
    }

    // MARK: - Image (PNG ↔ CF_DIB via WIC, see `+Image.swift`)

    public func readImage() async throws(KSError) -> Data? {
        try await readImageImpl()
    }

    public func writeImage(_ image: Data) async throws(KSError) {
        try await writeImageImpl(image)
    }

    // MARK: - Misc

    public func clear() async throws(KSError) {
        let result: Result<Void, KSError> = await MainActor.run {
            guard OpenClipboard(nil) else {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "OpenClipboard failed (\(GetLastError()))"))
            }
            defer { _ = CloseClipboard() }
            _ = EmptyClipboard()
            return .success(())
        }
        try result.unwrap()
    }

    public func hasFormat(_ format: String) async -> Bool {
        await MainActor.run {
            switch format.lowercased() {
            case "text":
                return IsClipboardFormatAvailable(UINT(CF_UNICODETEXT))
            case "image":
                return IsClipboardFormatAvailable(UINT(CF_BITMAP)) ||
                       IsClipboardFormatAvailable(UINT(CF_DIB))
            case "files":
                return IsClipboardFormatAvailable(UINT(CF_HDROP))
            default:
                return false
            }
        }
    }
}
#endif
