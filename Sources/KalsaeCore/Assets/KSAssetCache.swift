/// `KSAssetResolver` 결과를 위한 제한된 LRU 캐시.
///
/// Webview 페이지는 일반적으로 세션 동안 동일한 소수의 번들 자산
/// (`index.html`, 해시된 JS/CSS, 스플래시 이미지)을 반복해서 요청한다 —
/// 매번 디스크에서 다시 읽는 것이 자산 경로의 주요 비용이다.
/// 이 캐시는 이중 연결 최근 사용 목록으로 프런트된 딕셔너리에
/// 디코딩된 바이트를 저장한다.
///
/// 제거는 항목 수가 `maxEntries`를 초과하거나 누적 바이트 합계가
/// `maxBytes`를 초과할 때 중 먼저 도달하는 조건에서 트리거된다.
/// `maxBytes`보다 큰 단일 자산은 통과(해결되지만 캐시되지 않음)되어
/// 50MiB PNG가 4MiB 캐시를 비우지 못하게 한다.
///
/// 캐시는 내부적으로 비재귀적 잠금으로 동기화되며 `Sendable`이다.
/// `final class`이므로 `KSAssetResolver`(값 타입)가 안정적인 참조를
/// 유지할 수 있다.
internal import Foundation

public final class KSAssetCache: @unchecked Sendable {
    // @unchecked: NSLock — 가변 상태 동기화; 값 타입 래퍼에 액터는 부적합
    public let maxEntries: Int
    public let maxBytes: Int

    private let lock = NSLock()
    private var entries: [String: Node] = [:]
    private var head: Node?  // 가장 최근에 사용됨
    private var tail: Node?  // 가장 오래 전에 사용됨
    private var totalBytes: Int = 0

    public init(maxEntries: Int = 64, maxBytes: Int = 4 * 1024 * 1024) {
        precondition(maxEntries > 0, "maxEntries must be > 0")
        precondition(maxBytes > 0, "maxBytes must be > 0")
        self.maxEntries = maxEntries
        self.maxBytes = maxBytes
    }

    /// 캐시된 항목. 절대 해결 경로로 저장되어 동일 파일의
    /// 서로 다른 요청 표기가 하나의 슬롯을 공유한다.
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

    /// 계측/테스트용 스냅샷. 계산 비용이 저렴하다.
    public struct Stats: Sendable, Equatable {
        public let entries: Int
        public let totalBytes: Int
        public let hits: Int
        public let misses: Int
    }

    private var hits: Int = 0
    private var misses: Int = 0

    public func stats() -> Stats {
        lock.lock()
        defer { lock.unlock() }
        return Stats(
            entries: entries.count,
            totalBytes: totalBytes,
            hits: hits, misses: misses)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll(keepingCapacity: true)
        head = nil
        tail = nil
        totalBytes = 0
    }

    // MARK: - KSAssetResolver가 사용하는 내부 API

    func lookup(_ key: String) -> KSAssetResolver.Asset? {
        lock.lock()
        defer { lock.unlock() }
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

        lock.lock()
        defer { lock.unlock() }

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

    // MARK: - 이중 연결 리스트 (잠금 하에 유지)

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
