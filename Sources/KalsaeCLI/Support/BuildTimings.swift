/// `kalsae build` 파이프라인의 단계별 wall-clock 시간을 수집한다.
///
/// 최적화 작업 전 베이스라인 측정 / 최적화 후 회귀 검증용. 단발성 CLI 프로세스이므로
/// 인스턴스 하나가 빌드 전체 수명을 커버한다 (스레드 안전성 불필요).
public import Foundation

public struct KSBuildTimings: Sendable {
    public struct Entry: Sendable {
        public let stage: String
        public let nanoseconds: UInt64
        public var milliseconds: Double { Double(nanoseconds) / 1_000_000.0 }
    }

    private var entries: [Entry] = []
    private let clock = ContinuousClock()
    /// 별도로 캡처된 wall-clock 총 소요 시간 (병렬 단계가 있어 stage 합산이
    /// 실제 시간과 다른 경우, 호출자가 명시적으로 설정한다). nil이면
    /// `summary()` / `jsonData()` 는 stage 합산을 그대로 사용한다.
    public var wallClockNanoseconds: UInt64? = nil

    public init() {}

    /// `body`의 실행 시간을 측정해 `stage` 이름으로 기록한다.
    @discardableResult
    public mutating func measure<T>(_ stage: String, _ body: () throws -> T) rethrows -> T {
        let start = clock.now
        defer {
            let elapsed = clock.now - start
            entries.append(Entry(stage: stage, nanoseconds: nanos(elapsed)))
        }
        return try body()
    }

    /// 이미 측정된 Duration을 직접 기록한다. `measure(_:_:)`가 단일 블록을
    /// 둘러쌀 수 없는 경우(예: spawn / waitUntilExit가 다른 코드 사이에 끼어
    /// 있는 병렬 빌드 경로)에 사용한다.
    public mutating func record(_ stage: String, duration: Duration) {
        entries.append(Entry(stage: stage, nanoseconds: nanos(duration)))
    }

    /// 사람이 읽기 쉬운 표 형식 요약 (stdout용).
    public func summary() -> String {
        guard !entries.isEmpty else { return "" }
        let stageSumNs = entries.reduce(UInt64(0)) { $0 + $1.nanoseconds }
        let totalNs = wallClockNanoseconds ?? stageSumNs
        let totalMs = Double(totalNs) / 1_000_000.0
        let nameWidth = max(8, entries.map(\.stage.count).max() ?? 8)
        var lines: [String] = [
            "",
            "⏱  Build timings",
            "─────────────────────────────",
        ]
        for e in entries {
            // 퍼센트는 stage 합산 기준 — 병렬일 때도 각 stage의 상대 비중을 보여줌
            let pct = stageSumNs > 0 ? Double(e.nanoseconds) / Double(stageSumNs) * 100 : 0
            let name = e.stage.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            lines.append(
                "  \(name)  \(String(format: "%9.1f", e.milliseconds)) ms"
                    + "  (\(String(format: "%5.1f", pct))%)")
        }
        let totalLabel = wallClockNanoseconds != nil ? "WALL" : "TOTAL"
        let total = totalLabel.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
        lines.append("  \(total)  \(String(format: "%9.1f", totalMs)) ms")
        if wallClockNanoseconds != nil {
            let serial = Double(stageSumNs) / 1_000_000.0
            lines.append("  (stage sum: \(String(format: "%.1f", serial)) ms — overlap from parallel stages)")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// 기계 판독 가능한 JSON. `.build/kalsae-timings.json` 등에 직접 기록한다.
    public func jsonData() throws -> Data {
        struct Payload: Encodable {
            struct StagePayload: Encodable {
                let stage: String
                let ms: Double
            }
            let timestamp: String
            let totalMs: Double
            let stageSumMs: Double
            let stages: [StagePayload]
        }
        let stageSumMs =
            Double(entries.reduce(UInt64(0)) { $0 + $1.nanoseconds }) / 1_000_000.0
        let totalMs = wallClockNanoseconds.map { Double($0) / 1_000_000.0 } ?? stageSumMs
        let payload = Payload(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            totalMs: totalMs,
            stageSumMs: stageSumMs,
            stages: entries.map { .init(stage: $0.stage, ms: $0.milliseconds) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private func nanos(_ d: Duration) -> UInt64 {
        let comps = d.components
        let secsNs = UInt64(max(0, comps.seconds)) &* 1_000_000_000
        let attoNs = UInt64(max(0, comps.attoseconds / 1_000_000_000))
        return secsNs &+ attoNs
    }
}
