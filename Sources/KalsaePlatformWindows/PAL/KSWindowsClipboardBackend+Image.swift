#if os(Windows)
internal import WinSDK
internal import CKalsaeWV2
public import KalsaeCore
public import Foundation

// MARK: - 이미지(PNG) 클립보드 입출력
//
// Windows 클립보드는 표준 이미지 포맷으로 PNG가 아닌 `CF_DIB`(또는
// `CF_DIBV5`)을 사용한다. 따라서 read는 DIB → PNG, write는 PNG → DIB
// 변환을 거친다. 변환은 WIC 기반 C++ 쉬밌(`KSImage_*`)이 담당한다.

extension KSWindowsClipboardBackend {

    /// `CF_DIBV5`(우선) 또는 `CF_DIB`을 PNG 바이트로 변환해 돌려준다.
    /// 클립보드에 이미지 포맷이 없으면 `nil`.
    public func readImageImpl() async throws(KSError) -> Data? {
        let result: Result<Data?, KSError> = await MainActor.run {
            guard OpenClipboard(nil) else {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "OpenClipboard failed (\(GetLastError()))"))
            }
            defer { _ = CloseClipboard() }

            // CF_DIBV5 우선(메타데이터 더 풍부) → CF_DIB 폴백.
            var handle = GetClipboardData(UINT(CF_DIBV5))
            if handle == nil {
                handle = GetClipboardData(UINT(CF_DIB))
            }
            guard let handle else { return .success(nil) }

            let raw = GlobalLock(handle)
            guard let raw else {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "GlobalLock(CF_DIB) failed (\(GetLastError()))"))
            }
            let size = GlobalSize(handle)
            defer { _ = GlobalUnlock(handle) }
            if size == 0 { return .success(nil) }

            var outPtr: UnsafeMutablePointer<UInt8>? = nil
            var outLen: size_t = 0
            let hr = KSImage_DIBToPNG(
                raw.assumingMemoryBound(to: UInt8.self),
                Int(size),
                &outPtr, &outLen)
            if hr != 0 {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "KSImage_DIBToPNG failed (HRESULT=0x\(String(hr, radix: 16)))"))
            }
            guard let outPtr, outLen > 0 else { return .success(nil) }
            let data = Data(bytes: outPtr, count: Int(outLen))
            KSWV2_Free(outPtr)
            return .success(data)
        }
        return try result.unwrap()
    }

    /// PNG 바이트를 받아 `CF_DIB`로 클립보드에 쓴다.
    public func writeImageImpl(_ image: Data) async throws(KSError) {
        // 빈 페이로드는 거부.
        guard !image.isEmpty else {
            throw KSError(
                code: .invalidArgument,
                message: "writeImage: PNG payload is empty.")
        }

        // 1) PNG → DIB 변환은 COM 작업이라 MainActor에서.
        let dibResult: Result<Data, KSError> = await MainActor.run {
            var outPtr: UnsafeMutablePointer<UInt8>? = nil
            var outLen: size_t = 0
            let hr = image.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
                guard let base = raw.baseAddress else { return -1 }
                return KSImage_PNGToDIB(
                    base.assumingMemoryBound(to: UInt8.self),
                    raw.count,
                    &outPtr, &outLen)
            }
            if hr != 0 {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "KSImage_PNGToDIB failed (HRESULT=0x\(String(hr, radix: 16)))"))
            }
            guard let outPtr, outLen > 0 else {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "KSImage_PNGToDIB produced empty output."))
            }
            let data = Data(bytes: outPtr, count: Int(outLen))
            KSWV2_Free(outPtr)
            return .success(data)
        }
        let dib = try dibResult.unwrap()

        // 2) DIB을 클립보드에 SetClipboardData(CF_DIB).
        let setResult: Result<Void, KSError> = await MainActor.run {
            guard OpenClipboard(nil) else {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "OpenClipboard failed (\(GetLastError()))"))
            }
            defer { _ = CloseClipboard() }
            _ = EmptyClipboard()

            let bytes = dib.count
            guard let h = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(bytes)) else {
                return .failure(KSError(
                    code: .ioFailed,
                    message: "GlobalAlloc(\(bytes)) failed (\(GetLastError()))"))
            }
            let dst = GlobalLock(h)
            if let dst {
                dib.withUnsafeBytes { raw in
                    if let base = raw.baseAddress {
                        memcpy(dst, base, bytes)
                    }
                }
                _ = GlobalUnlock(h)
            } else {
                _ = GlobalFree(h)
                return .failure(KSError(
                    code: .ioFailed,
                    message: "GlobalLock(CF_DIB) failed (\(GetLastError()))"))
            }
            if SetClipboardData(UINT(CF_DIB), h) == nil {
                _ = GlobalFree(h)
                return .failure(KSError(
                    code: .ioFailed,
                    message: "SetClipboardData(CF_DIB) failed (\(GetLastError()))"))
            }
            // 성공 시 클립보드로 소유권 이전.
            return .success(())
        }
        try setResult.unwrap()
    }
}
#endif
