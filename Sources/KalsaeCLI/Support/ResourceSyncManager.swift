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
    /// 제거된 파일/디렉터리의 상대 경로 (forward-slash). `--no-prune`(noPrune)
    /// 모드에서는 항상 비어 있다. STDOUT 진단용으로만 사용한다 — `removed`
    /// 카운트와 길이가 일치한다.
    public var removedRels: [String]

    public init(
        copied: Int = 0,
        skipped: Int = 0,
        removed: Int = 0,
        failed: Int = 0,
        skippedReason: String? = nil,
        removedRels: [String] = []
    ) {
        self.copied = copied
        self.skipped = skipped
        self.removed = removed
        self.failed = failed
        self.skippedReason = skippedReason
        self.removedRels = removedRels
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
        preserved: Set<String> = ["kalsae.json"],
        fm: FileManager = .default
    ) throws -> KSResourceSyncReport {
        try sync(
            distURL: distURL,
            resourcesURL: resourcesURL,
            preserved: preserved,
            preservedGlobs: [],
            noPrune: false,
            fm: fm)
    }

    /// dist → Resources/ 증분 sync (glob 보존 + prune skip 지원).
    ///
    /// - Parameters:
    ///   - distURL: 프론트엔드 빌드 산출물.
    ///   - resourcesURL: SwiftPM 리소스 디렉터리.
    ///   - preserved: 보존할 leaf 파일명 (대소문자 구분).
    ///   - preservedGlobs: `KSConfig.build.preserveResources` 의 glob 패턴 목록.
    ///     상대 경로 (forward-slash) 기준으로 매칭한다. `selectors.json`,
    ///     `scripts/**` 같은 사용자 선언 보존 항목이 여기에 들어온다.
    ///   - noPrune: `true` 면 Pass 2 (orphan 제거) 자체를 건너뛴다.
    ///     `--no-prune` CLI 플래그가 이 모드를 사용한다.
    ///   - fm: 주입 가능한 FileManager.
    @discardableResult
    public static func sync(
        distURL: URL,
        resourcesURL: URL,
        preserved: Set<String> = ["kalsae.json"],
        preservedGlobs: [String] = [],
        noPrune: Bool = false,
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
        let pruneResult: (count: Int, rels: [String])
        if noPrune {
            pruneResult = (0, [])
        } else {
            pruneResult = try removeOrphans(
                resourcesURL: resourcesURL,
                distFileRels: entries.fileRels,
                distDirRels: entries.dirRels,
                preserved: preserved,
                preservedGlobs: preservedGlobs,
                fm: fm)
        }
        let (copied, skipped, failed) = try copyChanged(
            distURL: distURL,
            resourcesURL: resourcesURL,
            entries: entries.entries,
            preserved: preserved,
            fm: fm)

        return KSResourceSyncReport(
            copied: copied,
            skipped: skipped,
            removed: pruneResult.count,
            failed: failed,
            removedRels: pruneResult.rels)
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
        preservedGlobs: [String],
        fm: FileManager
    ) throws -> (count: Int, rels: [String]) {
        guard
            let it = fm.enumerator(
                at: resourcesURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return (0, []) }

        var orphanDirs: [(url: URL, rel: String)] = []
        var removedRels: [String] = []

        while let item = it.nextObject() as? URL {
            let rel = relativize(item.path, base: resourcesURL.path)
            if rel.isEmpty { continue }
            let leaf = (rel as NSString).lastPathComponent
            if preserved.contains(leaf) { continue }
            if matchesAnyGlob(rel: rel, patterns: preservedGlobs) { continue }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = values.isDirectory == true
            if isDir {
                if !distDirRels.contains(rel) {
                    // 디렉터리 자체나 그 안의 임의 자식이 preservedGlobs 에 걸리면
                    // 트리를 통째로 지우지 않는다. 빈 디렉터리는 자식 파일 제거 후
                    // 자연스럽게 남지 않으므로 별도 cleanup 은 생략.
                    if matchesAnyGlob(rel: rel, patterns: preservedGlobs) { continue }
                    if dirCoversPreservedGlob(rel: rel, patterns: preservedGlobs) { continue }
                    orphanDirs.append((item, rel))
                }
            } else if !distFileRels.contains(rel) {
                try fm.removeItem(at: item)
                removedRels.append(rel)
            }
        }

        // 깊은 디렉터리부터 제거 — 부모를 먼저 지우면 자식 walk 가 stale URL 을 본다.
        for entry in orphanDirs.sorted(by: { $0.url.path.count > $1.url.path.count }) {
            try? fm.removeItem(at: entry.url)
            removedRels.append(entry.rel + "/")
        }
        return (removedRels.count, removedRels)
    }

    /// `preservedGlobs` 중 하나라도 `rel`과 매칭하면 보존한다.
    /// `KSFSScope.glob`을 재사용해 `**`, `*`, `?` 동일 의미를 보장한다.
    private static func matchesAnyGlob(rel: String, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return false }
        for p in patterns where KSFSScope.glob(pattern: p, matches: rel) {
            return true
        }
        return false
    }

    /// 디렉터리 `rel` 내부의 *어떤* 자식이라도 `patterns` 중 하나와 매칭할 가능성이
    /// 있으면 `true`. probe suffix 로 깊은 경로 매칭을 흉내낸다 — 매칭이 되면
    /// 디렉터리 트리를 통째로 지우는 위험을 막는다.
    private static func dirCoversPreservedGlob(rel: String, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return false }
        let probe = rel + "/__ks_probe__"
        for p in patterns where KSFSScope.glob(pattern: p, matches: probe) {
            return true
        }
        return false
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
