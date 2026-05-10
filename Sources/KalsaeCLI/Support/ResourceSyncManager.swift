/// 프론트엔드 빌드 산출물(`dist/`)을 SwiftPM 리소스 디렉터리
/// (`Sources/<target>/Resources/`)로 증분 동기화한다.
///
/// `kalsae build` 의 parallel 경로가 swift build 가 끝난 뒤 dist 가
/// 갱신되어도 SwiftPM 리소스 묶음에 반영되도록 호출한다. 동작은
/// `robocopy /MIR` 또는 rsync 와 유사하다 — orphan 제거 후 size+mtime
/// 비교로 변경된 파일만 복사.
///
/// `BuildCommand.syncFrontendResourcesIfNeeded` 에서 추출된 로직.
/// `(distURL, resourcesURL)` 단위로 분리하여 단위 테스트가 쉽고
/// `BuildCommand` 의 코어 흐름이 짧아진다.
public import Foundation
internal import KalsaeCore

/// 동기화 결과 통계.
public struct KSResourceSyncReport: Sendable, Equatable {
    public var copied: Int
    public var skipped: Int
    public var removed: Int
    public var failed: Int
    public var skippedReason: String?

    public init(
        copied: Int = 0,
        skipped: Int = 0,
        removed: Int = 0,
        failed: Int = 0,
        skippedReason: String? = nil
    ) {
        self.copied = copied
        self.skipped = skipped
        self.removed = removed
        self.failed = failed
        self.skippedReason = skippedReason
    }

    /// 변경 사항이 있어 swift build 를 한 번 더 돌려야 하는지.
    public var didMutate: Bool { copied > 0 || removed > 0 }
}

public enum KSResourceSyncManager {
    /// dist 와 Resources/ 가 동일하거나 한쪽이 다른 쪽을 포함하는지 검사.
    /// 데모처럼 `Sources/<target>/Resources/kalsae.json` + `frontendDist:
    /// "Resources"` 조합이 정확히 이 함정에 걸린다 — Pass 2 orphan 제거가
    /// dist 자기 자신을 지울 위험이 있어 안전하게 skip 한다.
    public static func overlaps(distURL: URL, resourcesURL: URL) -> Bool {
        let normDist = distURL.standardizedFileURL.path
            .replacingOccurrences(of: "\\", with: "/")
        let normRes = resourcesURL.standardizedFileURL.path
            .replacingOccurrences(of: "\\", with: "/")
        return normDist == normRes
            || normDist.hasPrefix(normRes + "/")
            || normRes.hasPrefix(normDist + "/")
    }

    /// dist → Resources/ 증분 sync.
    /// - Parameters:
    ///   - distURL: 프론트엔드 빌드 산출물 (없으면 단순 skip).
    ///   - resourcesURL: SwiftPM 리소스 디렉터리 (없으면 단순 skip).
    ///   - preserved: 보존할 파일명 (대소문자 구분, 기본은 `kalsae.json` 변종).
    ///   - fm: 주입 가능한 FileManager (테스트용).
    /// - Returns: 복사/건너뜀/제거/실패 수 + 사유.
    @discardableResult
    public static func sync(
        distURL: URL,
        resourcesURL: URL,
        preserved: Set<String> = ["kalsae.json", "Kalsae.json"],
        fm: FileManager = .default
    ) throws -> KSResourceSyncReport {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resourcesURL.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            return KSResourceSyncReport(skippedReason: "resources directory missing")
        }

        if overlaps(distURL: distURL, resourcesURL: resourcesURL) {
            return KSResourceSyncReport(
                skippedReason:
                    "frontendDist (\(distURL.path)) overlaps Resources (\(resourcesURL.path))")
        }

        let entries = try enumerateDist(distURL: distURL, fm: fm)
        let removed = try removeOrphans(
            resourcesURL: resourcesURL,
            distFileRels: entries.fileRels,
            distDirRels: entries.dirRels,
            preserved: preserved,
            fm: fm)
        let (copied, skipped, failed) = try copyChanged(
            distURL: distURL,
            resourcesURL: resourcesURL,
            entries: entries.entries,
            preserved: preserved,
            fm: fm)

        return KSResourceSyncReport(
            copied: copied,
            skipped: skipped,
            removed: removed,
            failed: failed)
    }

    // MARK: - Pass 1: Enumerate dist

    struct DistEntry {
        let relPath: String  // forward-slash, no leading separator
        let isDirectory: Bool
        let size: Int64
        let mtime: Date?
    }

    private struct DistSnapshot {
        let entries: [DistEntry]
        let fileRels: Set<String>
        let dirRels: Set<String>
    }

    private static func enumerateDist(distURL: URL, fm: FileManager) throws -> DistSnapshot {
        var entries: [DistEntry] = []
        var fileRels: Set<String> = []
        var dirRels: Set<String> = []

        guard
            let it = fm.enumerator(
                at: distURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles])
        else {
            return DistSnapshot(entries: [], fileRels: [], dirRels: [])
        }

        while let src = it.nextObject() as? URL {
            let rel = relativize(src.path, base: distURL.path)
            if rel.isEmpty { continue }
            let values = try src.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            ])
            let isDir = values.isDirectory == true
            entries.append(
                DistEntry(
                    relPath: rel,
                    isDirectory: isDir,
                    size: Int64(values.fileSize ?? 0),
                    mtime: values.contentModificationDate))
            if isDir {
                dirRels.insert(rel)
            } else {
                fileRels.insert(rel)
            }
        }

        return DistSnapshot(entries: entries, fileRels: fileRels, dirRels: dirRels)
    }

    // MARK: - Pass 2: Remove orphans

    private static func removeOrphans(
        resourcesURL: URL,
        distFileRels: Set<String>,
        distDirRels: Set<String>,
        preserved: Set<String>,
        fm: FileManager
    ) throws -> Int {
        guard
            let it = fm.enumerator(
                at: resourcesURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return 0 }

        var orphanDirs: [URL] = []
        var removed = 0

        while let item = it.nextObject() as? URL {
            let rel = relativize(item.path, base: resourcesURL.path)
            if rel.isEmpty { continue }
            let leaf = (rel as NSString).lastPathComponent
            if preserved.contains(leaf) { continue }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = values.isDirectory == true
            if isDir {
                if !distDirRels.contains(rel) {
                    orphanDirs.append(item)
                }
            } else if !distFileRels.contains(rel) {
                try fm.removeItem(at: item)
                removed += 1
            }
        }

        // 깊은 디렉터리부터 제거 — 부모를 먼저 지우면 자식 walk 가 stale URL 을 본다.
        for dir in orphanDirs.sorted(by: { $0.path.count > $1.path.count }) {
            try? fm.removeItem(at: dir)
            removed += 1
        }
        return removed
    }

    // MARK: - Pass 3: Copy changed

    private static func copyChanged(
        distURL: URL,
        resourcesURL: URL,
        entries: [DistEntry],
        preserved: Set<String>,
        fm: FileManager
    ) throws -> (copied: Int, skipped: Int, failed: Int) {
        var copied = 0
        var skipped = 0
        var failed = 0

        for entry in entries {
            let src = distURL.appendingPathComponent(entry.relPath)
            let dst = resourcesURL.appendingPathComponent(entry.relPath)

            if entry.isDirectory {
                try fm.createDirectory(at: dst, withIntermediateDirectories: true)
                continue
            }

            if preserved.contains(dst.lastPathComponent),
                fm.fileExists(atPath: dst.path)
            {
                continue
            }

            // Incremental decision: size+mtime 매치 시 skip. FAT32/SMB 의 2초
            // 양자화를 위해 1초 슬랙 허용.
            if let dstAttrs = try? fm.attributesOfItem(atPath: dst.path),
                let dSize = (dstAttrs[.size] as? NSNumber)?.int64Value,
                let dMtime = dstAttrs[.modificationDate] as? Date,
                dSize == entry.size,
                let sMtime = entry.mtime,
                abs(dMtime.timeIntervalSince(sMtime)) < 1.0
            {
                skipped += 1
                continue
            }

            do {
                try fm.createDirectory(
                    at: dst.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
                try fm.copyItem(at: src, to: dst)
                copied += 1
            } catch {
                failed += 1
            }
        }

        return (copied, skipped, failed)
    }

    // MARK: - Helpers

    /// `path`에서 `base` 접두를 제거해 상대 경로를 만든다. `replacingOccurrences`
    /// 는 `base`가 path 내부에서 다시 등장할 때 잘못된 위치를 지우므로
    /// **prefix 매칭**으로만 한 번 제거한다. 일치하지 않으면 path를 그대로
    /// 반환한다 (방어적). 결과는 항상 `/` 구분자로 정규화된다.
    internal static func relativize(_ path: String, base: String) -> String {
        let normalize: (String) -> String = { $0.replacingOccurrences(of: "\\", with: "/") }
        let p = normalize(path)
        let b = normalize(base)
        let stripped: String
        if p.hasPrefix(b) {
            stripped = String(p.dropFirst(b.count))
        } else {
            stripped = p
        }
        return stripped.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
