/// Kalsae 패키저에서 사용하는 OS 네이티브 zip 아카이버입니다.
///
/// Windows에서 이전에 사용하던 PowerShell `Compress-Archive` 외부 호출(shell-out)을
/// Windows 10 1803+부터 탑재된 BSD `tar.exe`로 대체하였습니다. 이 방식은 다음을 수행합니다:
///   * ~150 ms PowerShell.exe 시작 시간을 생략하고,
///   * ~200 ms `Add-Type System.IO.Compression.FileSystem` JIT 로드를 생략하며,
///   * 여전히 표준 PKZIP 아카이브를 생성합니다 (libarchive).
///
/// macOS는 코드 서명 및 notarization이 의존하는 확장 속성을 보존하는 `ditto`를 계속 사용합니다.
/// Linux는 `/usr/bin/zip`을 계속 사용합니다.
///
/// 모든 신뢰할 수 없는 경로 데이터는 별도의 `arguments`(필요한 경우 `currentDirectoryURL`과 함께)로 전달되며 —
/// 절대 셸 스크립트에 문자열 보간되지 않기 때문에 —
/// 작은따옴표, 유니코드, 공백이 포함된 경로도 구조적으로 안전합니다.
public import Foundation

public enum KSZipArchiverError: Error, CustomStringConvertible {
    case sourceMissing(URL)
    case archiveCreationFailed(exit: Int32, tool: String, stderr: String)
    case toolNotFound(String)

    public var description: String {
        switch self {
        case .sourceMissing(let u):
            return "Source not found at \(u.path)"
        case .archiveCreationFailed(let code, let tool, let err):
            let trimmed = err.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? "\(tool) exited \(code)"
                : "\(tool) exited \(code): \(trimmed)"
        case .toolNotFound(let path):
            return "Required archiver not found at \(path)"
        }
    }
}

public enum KSZipArchiver {
    /// 디렉터리(`directory`)의 *내용*을 `archive` zip으로 압축한다.
    /// 결과 zip의 최상위 항목들은 `directory`의 자식들이며, `directory`
    /// 자체는 포함되지 않는다 (예전 PowerShell `CreateFromDirectory` 호환).
    /// `archive`가 이미 있으면 덮어쓴다.
    public static func zip(directory: URL, to archive: URL) throws {
        try runArchiver(directory: directory, archive: archive, keepParent: false)
    }

    /// `zip(directory:to:)`의 비동기 변종. 큰 디렉터리 압축이 호출 스레드를
    /// 블로킹하지 않도록 백그라운드 큐에서 실행한다.
    public static func zipAsync(directory: URL, to archive: URL) async throws {
        try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.zip(directory: directory, to: archive)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// 디렉터리를 zip하되, 최상위에 부모 디렉터리 이름을 유지한다 (예:
    /// macOS `.app` 번들을 `Foo.app/...` 구조로 압축할 때). `ditto -k --keepParent`
    /// 동작과 동일.
    public static func zipKeepingParent(directory: URL, to archive: URL) throws {
        try runArchiver(directory: directory, archive: archive, keepParent: true)
    }

    /// `archive` zip 의 내용을 `destination` 디렉터리에 추출한다.
    /// `destination` 은 이미 존재해야 한다 (없으면 생성). 기존 파일은 덮어쓴다.
    ///
    /// Windows: 내장 `tar.exe` (libarchive) 를 사용 — PowerShell `Expand-Archive`
    ///   를 대체. macOS: `/usr/bin/ditto`. Linux: `/usr/bin/unzip`.
    public static func unzip(archive: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: archive.path) else {
            throw KSZipArchiverError.sourceMissing(archive)
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        #if os(Windows)
            let toolPath = "C:\\Windows\\System32\\tar.exe"
            guard fm.fileExists(atPath: toolPath) else {
                throw KSZipArchiverError.toolNotFound(toolPath)
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: toolPath)
            p.arguments = ["-x", "-f", archive.path, "-C", destination.path]
            try runAndCheck(p, tool: "tar")
        #elseif os(macOS)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            // ditto -xk <src.zip> <destDir>
            p.arguments = ["-x", "-k", archive.path, destination.path]
            try runAndCheck(p, tool: "ditto")
        #else
            let toolPath = "/usr/bin/unzip"
            guard fm.fileExists(atPath: toolPath) else {
                throw KSZipArchiverError.toolNotFound(toolPath)
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: toolPath)
            p.arguments = ["-o", "-q", archive.path, "-d", destination.path]
            try runAndCheck(p, tool: "unzip")
        #endif
    }

    // MARK: - Implementation

    private static func runArchiver(
        directory: URL, archive: URL, keepParent: Bool
    ) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            throw KSZipArchiverError.sourceMissing(directory)
        }

        if fm.fileExists(atPath: archive.path) {
            try fm.removeItem(at: archive)
        }
        try fm.createDirectory(
            at: archive.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        #if os(Windows)
            try runTarWindows(
                directory: directory, archive: archive, keepParent: keepParent)
        #elseif os(macOS)
            try runDittoMac(
                directory: directory, archive: archive, keepParent: keepParent)
        #else
            try runZipUnix(
                directory: directory, archive: archive, keepParent: keepParent)
        #endif
    }

    #if os(Windows)
        /// Windows 10 1803+ 에 내장된 BSD `tar.exe`(libarchive)를 사용한다.
        /// `-a -cf <out.zip>` 형태로 확장자에 따라 zip 포맷을 자동 선택한다.
        ///
        /// `keepParent`:
        ///   * false → `tar -C <directory> -cf out.zip .` (내용만)
        ///   * true  → `tar -C <directory.parent> -cf out.zip <directory.lastPath>`
        private static func runTarWindows(
            directory: URL, archive: URL, keepParent: Bool
        ) throws {
            let toolPath = "C:\\Windows\\System32\\tar.exe"
            guard FileManager.default.fileExists(atPath: toolPath) else {
                throw KSZipArchiverError.toolNotFound(toolPath)
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: toolPath)
            // `-a` makes tar pick the archive format from the extension
            // (`.zip` → PKZIP).
            if keepParent {
                p.arguments = [
                    "-a", "-c", "-f", archive.path,
                    "-C", directory.deletingLastPathComponent().path,
                    directory.lastPathComponent,
                ]
            } else {
                p.arguments = [
                    "-a", "-c", "-f", archive.path,
                    "-C", directory.path, ".",
                ]
            }
            try runAndCheck(p, tool: "tar")
        }
    #endif

    #if os(macOS)
        private static func runDittoMac(
            directory: URL, archive: URL, keepParent: Bool
        ) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            if keepParent {
                p.arguments = [
                    "-c", "-k", "--keepParent",
                    directory.path, archive.path,
                ]
            } else {
                p.arguments = [
                    "-c", "-k",
                    directory.path, archive.path,
                ]
            }
            try runAndCheck(p, tool: "ditto")
        }
    #endif

    #if !os(Windows) && !os(macOS)
        private static func runZipUnix(
            directory: URL, archive: URL, keepParent: Bool
        ) throws {
            let toolPath = "/usr/bin/zip"
            guard FileManager.default.fileExists(atPath: toolPath) else {
                throw KSZipArchiverError.toolNotFound(toolPath)
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: toolPath)
            if keepParent {
                p.arguments = ["-r", "-q", archive.path, directory.lastPathComponent]
                p.currentDirectoryURL = directory.deletingLastPathComponent()
            } else {
                p.arguments = ["-r", "-q", archive.path, "."]
                p.currentDirectoryURL = directory
            }
            try runAndCheck(p, tool: "zip")
        }
    #endif

    /// `Process` 실행 + 에러 캡처. stderr를 파이프로 받아 진단에 포함시킨다.
    private static func runAndCheck(_ p: Process, tool: String) throws {
        let errPipe = Pipe()
        p.standardError = errPipe
        // stdout은 읽을 일이 없고 널 디바이스로 돌려서 파이프 버퍼 포화 시
        // 잠재적 데이터 경쟁(deadlock) 가능성을 등평한다 (tar/ditto/zip이
        // 조용한 quiet 플래그로 사용되지만 방어적으로 적용).
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            throw KSZipArchiverError.archiveCreationFailed(
                exit: p.terminationStatus, tool: tool, stderr: stderr)
        }
    }
}
