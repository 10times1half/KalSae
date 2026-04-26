public import Foundation

/// Bounded LRU cache for `KSAssetResolver` results.
///
/// Webview pages typically request the same handful of bundle assets
/// (`index.html`, hashed JS/CSS, splash images) repeatedly during a
/// session — re-reading them from disk every time is the dominant
/// cost in the asset path. This cache stores the decoded bytes in a
/// dictionary fronted by a doubly-linked recency list.
///
/// Eviction triggers when **either** the entry count exceeds
/// `maxEntries` **or** the cumulative byte total exceeds `maxBytes`,
/// whichever comes first. Single assets larger than `maxBytes` are
/// pass-through (resolved but not cached) so that a 50 MiB PNG can't
/// flush a 4 MiB cache.
///
/// The cache is internally synchronised with a non-recursive lock and
/// is `Sendable`. It's an `final class` so `KSAssetResolver` (a value
/// type) can carry a stable reference to it.
public final class KSAssetCache: @unchecked Sendable {
    public let maxEntries: Int
    public let maxBytes: Int

    private let lock = NSLock()
    private var entries: [String: Node] = [:]
    private var head: Node?  // most recently used
    private var tail: Node?  // least recently used
    private var totalBytes: Int = 0

    public init(maxEntries: Int = 64, maxBytes: Int = 4 * 1024 * 1024) {
        precondition(maxEntries > 0, "maxEntries must be > 0")
        precondition(maxBytes > 0, "maxBytes must be > 0")
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
    }

    /// Cached entry. Stored under the absolute resolved path so that
    /// distinct request spellings of the same file share a slot.
    fileprivate final class Node {
        let key: String
        let asset: KSAssetResolver.Asset
        let bytes: Int
        var prev: Node?
        var next: Node?
        init(key: String, asset: KSAssetResolver.Asset) {
            self.key = key
            self.asset = asset
            self.bytes = asset.data.count
        }
    }

    /// Snapshot for instrumentation/tests. Cheap to compute.
    public struct Stats: Sendable, Equatable {
        public let entries: Int
        public let totalBytes: Int
        public let hits: Int
        public let misses: Int
    }

    private var hits: Int = 0
    private var misses: Int = 0

    public func stats() -> Stats {
        lock.lock(); defer { lock.unlock() }
        return Stats(entries: entries.count,
                     totalBytes: totalBytes,
                     hits: hits, misses: misses)
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(keepingCapacity: true)
        head = nil; tail = nil
        totalBytes = 0
    }

    // MARK: - Internal API used by KSAssetResolver

    func lookup(_ key: String) -> KSAssetResolver.Asset? {
        lock.lock(); defer { lock.unlock() }
        guard let node = entries[key] else {
            misses &+= 1
            return nil
        }
        hits &+= 1
        moveToHead(node)
        return node.asset
    }

    func store(_ key: String, _ asset: KSAssetResolver.Asset) {
        let bytes = asset.data.count
        // 단일 자산이 캐시 한계보다 크면 캐시 비활성 — 한 큰 자산이
        // 정상 hot set을 다 밀어내는 것을 막는다.
        if bytes > maxBytes { return }

        lock.lock(); defer { lock.unlock() }

        if let existing = entries[key] {
            // 같은 키 갱신: 바이트 회계 조정 후 노드 교체.
            totalBytes -= existing.bytes
            unlink(existing)
            entries.removeValue(forKey: key)
        }

        let node = Node(key: key, asset: asset)
        entries[key] = node
        addToHead(node)
        totalBytes += bytes

        evictUntilWithinLimits()
    }

    private func evictUntilWithinLimits() {
        while entries.count > maxEntries || totalBytes > maxBytes {
            guard let victim = tail else { return }
            unlink(victim)
            entries.removeValue(forKey: victim.key)
            totalBytes -= victim.bytes
        }
    }

    // MARK: - Doubly-linked list (held under lock)

    private func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func moveToHead(_ node: Node) {
        guard head !== node else { return }
        unlink(node)
        addToHead(node)
    }

    private func unlink(_ node: Node) {
        let p = node.prev
        let n = node.next
        p?.next = n
        n?.prev = p
        if head === node { head = n }
        if tail === node { tail = p }
        node.prev = nil
        node.next = nil
    }
}
