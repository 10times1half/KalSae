public import Foundation
internal import KalsaeCore

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
        var totalBytes = 0
        var entries: [KSStoreZip.Entry] = []
        entries.reserveCapacity(contents.count)
        let prefixWin = distURL.path + "\\"
        let prefixUnix = distURL.path + "/"

        for fileURL in contents {
            var rel = fileURL.path
            if rel.hasPrefix(prefixWin) {
                rel = String(rel.dropFirst(prefixWin.count))
            } else if rel.hasPrefix(prefixUnix) {
                rel = String(rel.dropFirst(prefixUnix.count))
            }
            rel = rel.replacingOccurrences(of: "\\", with: "/")

            let bytes = try Data(contentsOf: fileURL)
            totalBytes += bytes.count
            entries.append(KSStoreZip.Entry(name: rel, data: bytes))
        }

        let zipData = KSStoreZip.write(entries: entries)

        return Report(
            zipData: zipData,
            fileCount: entries.count,
            totalUncompressedBytes: totalBytes,
            relativePaths: entries.map(\.name).sorted())
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
