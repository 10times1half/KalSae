public import Foundation

/// Standalone 임베드용 프론트엔드 번들 zip 생성기.
///
/// 현재 단계에서는 dist 디렉터리의 내용을 zip으로 묶어 메모리 `Data`로 반환한다.
/// 이후 단계에서 이 바이트를 PE `RCDATA`로 주입한다.
public enum KSAssetZipBuilder {
    public struct Report: Sendable {
        public let zipData: Data
        public let fileCount: Int
        public let totalUncompressedBytes: Int
        public let relativePaths: [String]

        public init(
            zipData: Data,
            fileCount: Int,
            totalUncompressedBytes: Int,
            relativePaths: [String]
        ) {
            self.zipData = zipData
            self.fileCount = fileCount
            self.totalUncompressedBytes = totalUncompressedBytes
            self.relativePaths = relativePaths
        }
    }

    public static func build(from distURL: URL) throws -> Report {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: distURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw KSZipArchiverError.sourceMissing(distURL)
        }

        let contents = try enumerateFiles(in: distURL, fm: fm)
        let totalBytes = try contents.reduce(into: 0) { partial, file in
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            partial += values.fileSize ?? 0
        }

        let tempArchive = fm.temporaryDirectory
            .appendingPathComponent("kalsae-embedded-assets-\(UUID().uuidString)")
            .appendingPathExtension("zip")

        defer { try? fm.removeItem(at: tempArchive) }

        try KSZipArchiver.zip(directory: distURL, to: tempArchive)
        let zipData = try Data(contentsOf: tempArchive)
        let relPaths = contents.map {
            $0.path.replacingOccurrences(of: distURL.path + "\\", with: "")
                .replacingOccurrences(of: distURL.path + "/", with: "")
                .replacingOccurrences(of: "\\", with: "/")
        }.sorted()

        return Report(
            zipData: zipData,
            fileCount: relPaths.count,
            totalUncompressedBytes: totalBytes,
            relativePaths: relPaths)
    }

    private static func enumerateFiles(in root: URL, fm: FileManager) throws -> [URL] {
        guard
            let e = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in e {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
