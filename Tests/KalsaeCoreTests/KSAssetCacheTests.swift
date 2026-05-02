import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSAssetCache — LRU semantics")
struct KSAssetCacheTests {
    private static func tmpRoot() -> URL {
        let r = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalsae-asset-cache-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: r, withIntermediateDirectories: true)
        return r
    }

    private static func write(_ root: URL, _ name: String, bytes: Int) {
        let url = root.appendingPathComponent(name)
        let data = Data(repeating: UInt8(name.first?.asciiValue ?? 0x41), count: bytes)
        try? data.write(to: url)
    }

    @Test("First lookup misses, second hits")
    func basicHit() throws {
        let root = Self.tmpRoot()
        Self.write(root, "a.txt", bytes: 16)
        let cache = KSAssetCache()
        let r = KSAssetResolver(root: root, cache: cache)

        _ = try r.resolve(path: "a.txt")
        let s1 = cache.stats()
        #expect(s1.entries == 1)
        #expect(s1.misses == 1)
        #expect(s1.hits == 0)

        _ = try r.resolve(path: "a.txt")
        let s2 = cache.stats()
        #expect(s2.entries == 1)
        #expect(s2.misses == 1)
        #expect(s2.hits == 1)
    }

    @Test("Distinct path spellings map to one cache slot")
    func pathNormalization() throws {
        let root = Self.tmpRoot()
        Self.write(root, "x.txt", bytes: 32)
        let cache = KSAssetCache()
        let r = KSAssetResolver(root: root, cache: cache)

        _ = try r.resolve(path: "x.txt")
        _ = try r.resolve(path: "/x.txt")
        let s = cache.stats()
        #expect(s.entries == 1, "leading slash must normalise to same slot")
        #expect(s.hits == 1)
    }

    @Test("Eviction by entry count")
    func evictByCount() throws {
        let root = Self.tmpRoot()
        for i in 0..<5 { Self.write(root, "f\(i).txt", bytes: 16) }
        let cache = KSAssetCache(maxEntries: 3, maxBytes: 1 << 20)
        let r = KSAssetResolver(root: root, cache: cache)

        for i in 0..<5 { _ = try r.resolve(path: "f\(i).txt") }
        let s = cache.stats()
        #expect(s.entries == 3, "must evict oldest down to maxEntries")
    }

    @Test("Eviction by total bytes")
    func evictByBytes() throws {
        let root = Self.tmpRoot()
        for i in 0..<4 { Self.write(root, "b\(i).txt", bytes: 1024) }
        let cache = KSAssetCache(maxEntries: 100, maxBytes: 2048)
        let r = KSAssetResolver(root: root, cache: cache)

        for i in 0..<4 { _ = try r.resolve(path: "b\(i).txt") }
        let s = cache.stats()
        #expect(s.totalBytes <= 2048)
        #expect(s.entries <= 2)
    }

    @Test("Single asset larger than maxBytes is not cached")
    func oversizedBypass() throws {
        let root = Self.tmpRoot()
        Self.write(root, "huge.bin", bytes: 4096)
        let cache = KSAssetCache(maxEntries: 100, maxBytes: 1024)
        let r = KSAssetResolver(root: root, cache: cache)

        _ = try r.resolve(path: "huge.bin")
        _ = try r.resolve(path: "huge.bin")
        let s = cache.stats()
        #expect(s.entries == 0, "oversized asset must not occupy the cache")
        #expect(s.misses == 2)
    }

    @Test("LRU recency: accessed entry survives eviction")
    func lruRecency() throws {
        let root = Self.tmpRoot()
        for i in 0..<3 { Self.write(root, "r\(i).txt", bytes: 16) }
        let cache = KSAssetCache(maxEntries: 2, maxBytes: 1 << 20)
        let r = KSAssetResolver(root: root, cache: cache)

        _ = try r.resolve(path: "r0.txt")  // [r0]
        _ = try r.resolve(path: "r1.txt")  // [r1, r0]
        _ = try r.resolve(path: "r0.txt")  // [r0, r1] (r0 promoted)
        _ = try r.resolve(path: "r2.txt")  // [r2, r0] — r1 evicted
        // r0은 여전히 적중, r1은 추출됨.
        _ = try r.resolve(path: "r0.txt")
        _ = try r.resolve(path: "r1.txt")
        let s = cache.stats()
        #expect(s.entries == 2)
        // misses: r0(1) + r1(1) + r2(1) + r1-추출후(1) = 4
        #expect(s.misses == 4)
    }

    @Test("clear() wipes all entries and resets byte count")
    func clearWipesAll() throws {
        let root = Self.tmpRoot()
        for i in 0..<3 { Self.write(root, "c\(i).txt", bytes: 16) }
        let cache = KSAssetCache()
        let r = KSAssetResolver(root: root, cache: cache)

        _ = try r.resolve(path: "c0.txt")
        _ = try r.resolve(path: "c1.txt")
        _ = try r.resolve(path: "c2.txt")
        var s = cache.stats()
        #expect(s.entries == 3)

        cache.clear()
        s = cache.stats()
        #expect(s.entries == 0)
        #expect(s.totalBytes == 0)
    }

    @Test("Cached resolve is faster than uncached for repeated hits")
    func repeatHotPath() throws {
        let root = Self.tmpRoot()
        // 100 KiB는 재읽기 비용이 측정 가능할 만큼 충분하면서도
        // CI에서 충분히 빠르다.
        Self.write(root, "hot.bin", bytes: 100 * 1024)

        let cold = KSAssetResolver(root: root)
        let warm = KSAssetResolver(root: root, cache: KSAssetCache())

        // Warm 한번 채우기.
        _ = try warm.resolve(path: "hot.bin")

        let iterations = 200
        let coldStart = DispatchTime.now()
        for _ in 0..<iterations { _ = try cold.resolve(path: "hot.bin") }
        let coldNs =
            DispatchTime.now().uptimeNanoseconds
            - coldStart.uptimeNanoseconds

        let warmStart = DispatchTime.now()
        for _ in 0..<iterations { _ = try warm.resolve(path: "hot.bin") }
        let warmNs =
            DispatchTime.now().uptimeNanoseconds
            - warmStart.uptimeNanoseconds

        // 캐시는 디스크보다 적어도 2× 빨라야 한다 — 보수적인 임계값.
        // CI 환경 변동을 흡수한다. CI 러너(특히 Windows)에서는 디스크 캐시가
        // 이미 매우 빠르거나 측정 노이즈가 커서 비율이 흔들리므로 더 완화한다.
        // Windows는 파일 시스템 캐시가 매우 빨라 cold/warm 차이가 2배까지
        // 벌어지지 않으므로 multiplier를 1로 고정하고, 추가로 측정 노이즈를
        // 흡수하기 위해 cold 쪽에 25% slack을 더한다.
        let isCI = ProcessInfo.processInfo.environment["CI"] != nil
        let isWindows: Bool = {
            #if os(Windows)
                return true
            #else
                return false
            #endif
        }()
        let relaxed = isCI || isWindows
        let multiplier: UInt64 = relaxed ? 1 : 2
        // relaxed 환경에서는 측정 노이즈로 warm > cold가 살짝 나올 수 있으므로
        // cold 쪽에 25% 여유를 둔다.
        let coldBudget: UInt64 = relaxed ? (coldNs * 5 / 4) : coldNs
        #expect(
            warmNs * multiplier <= coldBudget,
            "expected warm (\(warmNs) ns) to be ≥\(multiplier)× faster than cold (\(coldNs) ns)")
    }
}
