/// 디렉터리 콘텐츠의 mtime/크기 변동을 폴링으로 감지하는 가벼운 watcher.
///
/// 의도적으로 OS 네이티브 watch API(FSEvents/inotify/ReadDirectoryChangesW)를
/// 쓰지 않는다 — 이 모듈은 Foundation만으로 모든 플랫폼에서 동작해야 하고,
/// 사용 사례(dev 라이브 리로드)는 50–500ms 폴링 간격이면 충분하다.
///
/// 사용 예:
/// ```swift
/// let watcher = KSAssetWatcher(root: dist, interval: .milliseconds(300))
/// let task = Task { await watcher.run { await app.reload() } }
/// // ...
/// task.cancel() // 종료 시
/// ```
///
/// 동작 규칙:
/// - 첫 스캔의 fingerprint는 baseline. 변경 이벤트는 그 이후의 변동에만 발생.
/// - `debounce`(기본 200ms)이 지나기 전 추가 변경은 한 번으로 합쳐진다.
/// - cancellation은 협조적이다 — `run` 안의 sleep이 깨어날 때 확인.
public import Foundation

public actor KSAssetWatcher {
    public let root: URL
    public let interval: Duration
    public let debounce: Duration

    public init(
        root: URL,
        interval: Duration = .milliseconds(300),
        debounce: Duration = .milliseconds(200)
    ) {
        self.root = root
        self.interval = interval
        self.debounce = debounce
    }

    /// `onChange`를 변경이 감지될 때마다 호출한다. 작업이 취소될 때까지 반복.
    /// `onChange`는 `Sendable` 클로저이며, 다음 폴링은 onChange가 반환된 뒤에
    /// 진행된다 (직렬 실행).
    public func run(onChange: @Sendable @escaping () async -> Void) async {
        var fingerprint = computeFingerprint()
        var lastFire: ContinuousClock.Instant? = nil

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            let next = computeFingerprint()
            if next == fingerprint { continue }

            // 디바운스: 마지막 fire 이후 debounce 미경과면 fingerprint만 갱신하고
            // 다음 tick까지 대기.
            let now = ContinuousClock.now
            if let last = lastFire, last.duration(to: now) < debounce {
                fingerprint = next
                continue
            }
            fingerprint = next
            lastFire = now
            await onChange()
        }
    }

    /// 1회 스냅샷. (path, mtime, size) 세트를 정렬하여 해시한다.
    nonisolated func computeFingerprint() -> Int {
        var hasher = Hasher()
        let fm = FileManager.default
        guard
            let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles])
        else {
            return 0
        }

        var entries: [(String, TimeInterval, Int)] = []
        for case let url as URL in enumerator {
            let v = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard v?.isRegularFile == true else { continue }
            let mtime = v?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = v?.fileSize ?? 0
            entries.append((url.path, mtime, size))
        }
        entries.sort { $0.0 < $1.0 }
        for (p, m, s) in entries {
            hasher.combine(p)
            hasher.combine(m)
            hasher.combine(s)
        }
        return hasher.finalize()
    }
}
