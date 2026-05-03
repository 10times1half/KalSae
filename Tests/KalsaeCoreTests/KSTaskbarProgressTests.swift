import Foundation
import Testing

@testable import KalsaeCore

@Suite("KSTaskbarProgress")
struct KSTaskbarProgressTests {

    // MARK: - 1. Codable round-trip

    @Test("KSTaskbarProgress.none round-trip")
    func roundTripNone() throws {
        let original = KSTaskbarProgress.none
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KSTaskbarProgress.self, from: data)
        #expect(decoded == original)
    }

    @Test("KSTaskbarProgress.indeterminate round-trip")
    func roundTripIndeterminate() throws {
        let original = KSTaskbarProgress.indeterminate
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KSTaskbarProgress.self, from: data)
        #expect(decoded == original)
    }

    @Test("KSTaskbarProgress.normal(0.5) round-trip")
    func roundTripNormal() throws {
        let original = KSTaskbarProgress.normal(0.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KSTaskbarProgress.self, from: data)
        #expect(decoded == original)
    }

    @Test("KSTaskbarProgress.error(0.75) round-trip")
    func roundTripError() throws {
        let original = KSTaskbarProgress.error(0.75)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KSTaskbarProgress.self, from: data)
        #expect(decoded == original)
    }

    @Test("KSTaskbarProgress.paused(0.25) round-trip")
    func roundTripPaused() throws {
        let original = KSTaskbarProgress.paused(0.25)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KSTaskbarProgress.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - 2. JSON 와이어 형식 검증

    @Test("KSTaskbarProgress.none은 {\"type\":\"none\"}으로 인코딩된다")
    func noneEncodesCorrectly() throws {
        let data = try JSONEncoder().encode(KSTaskbarProgress.none)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["type"] as? String == "none")
        #expect(json?["value"] == nil)
    }

    @Test("KSTaskbarProgress.normal(0.8)은 value 필드를 포함한다")
    func normalEncodesWithValue() throws {
        let data = try JSONEncoder().encode(KSTaskbarProgress.normal(0.8))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["type"] as? String == "normal")
        #expect(json?["value"] as? Double == 0.8)
    }

    @Test("KSTaskbarProgress.indeterminate은 {\"type\":\"indeterminate\"}으로 인코딩된다")
    func indeterminateEncodesCorrectly() throws {
        let data = try JSONEncoder().encode(KSTaskbarProgress.indeterminate)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["type"] as? String == "indeterminate")
    }

    // MARK: - 3. value 없는 JSON에서 디코딩 시 기본값 0

    @Test("value 필드 없이 디코딩 시 0.0으로 기본값 적용")
    func decodeWithoutValueDefaultsToZero() throws {
        let json = Data(#"{"type":"normal"}"#.utf8)
        let decoded = try JSONDecoder().decode(KSTaskbarProgress.self, from: json)
        #expect(decoded == .normal(0.0))
    }

    // MARK: - 4. Equatable

    @Test("동일한 KSTaskbarProgress 값은 같다고 판단된다")
    func equatable() {
        #expect(KSTaskbarProgress.none == .none)
        #expect(KSTaskbarProgress.indeterminate == .indeterminate)
        #expect(KSTaskbarProgress.normal(0.5) == .normal(0.5))
        #expect(KSTaskbarProgress.error(1.0) == .error(1.0))
        #expect(KSTaskbarProgress.paused(0.0) == .paused(0.0))
    }

    @Test("다른 KSTaskbarProgress 값은 다르다고 판단된다")
    func notEqual() {
        #expect(KSTaskbarProgress.none != .indeterminate)
        #expect(KSTaskbarProgress.normal(0.5) != .normal(0.6))
        #expect(KSTaskbarProgress.normal(0.5) != .error(0.5))
    }
}
