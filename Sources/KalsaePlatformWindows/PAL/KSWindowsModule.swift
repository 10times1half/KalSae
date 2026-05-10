#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore
    internal import Foundation

    /// Windows 전용 공통 유틸. PAL 백엔드 사이의 중복을 흡수한다.
    internal enum KSWindowsModule {
        /// Resolves the absolute path of the running EXE via
        /// `GetModuleFileNameW`. Returns the long-path form (no MAX_PATH
        /// truncation — the buffer is grown until the call succeeds).
        ///
        /// `KSWindowsAutostartBackend.resolveModulePath` /
        /// `KSWindowsDeepLinkBackend.resolveModulePath` 두 곳에 동일하게
        /// 들어 있던 코드를 한 곳으로 모은 헬퍼.
        internal static func resolvePath() throws(KSError) -> String {
            var capacity = 1024
            while capacity <= 32768 {
                var buf = [UInt16](repeating: 0, count: capacity)
                let rc = GetModuleFileNameW(nil, &buf, DWORD(capacity))
                if rc == 0 {
                    let err = Int(GetLastError())
                    throw KSError(
                        code: .ioFailed,
                        message: "GetModuleFileNameW failed (\(err))",
                        data: .int(err))
                }
                // 버퍼가 충분치 않으면 ERROR_INSUFFICIENT_BUFFER가 설정되며
                // rc == capacity가 된다. 두 배로 늘려 재시도.
                if Int(rc) == capacity {
                    capacity *= 2
                    continue
                }
                return String(decoding: buf.prefix(Int(rc)), as: UTF16.self)
            }
            throw KSError(
                code: .ioFailed,
                message: "GetModuleFileNameW: path > 32K characters")
        }
    }
#endif
