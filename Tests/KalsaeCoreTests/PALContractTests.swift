import Foundation
import Testing

/// Minimal reference implementation for the contract suite. Stores text
/// and image bytes in actor state. Production backends should pass the
/// **same** contract test (the contract is the spec).
@testable import KalsaeCore

// MARK: - PAL Contract Tests
//
// 이 파일은 PAL 백엔드 프로토콜의 *행동 계약*을 정의하는 재사용 가능한
// 테스트 스캐폴딩이다. 각 `…Contract` 타입은 백엔드 팩토리를 받아
// 어떤 구현체이든 동일한 일관성 불변식을 만족하는지 검증한다.
//
//   - 기본 익스텐션 슈트는 `unsupportedPlatform` throw 동작을 못 박는다.
//   - 인-메모리 참조 구현 슈트는 동일한 계약 묶음이 실제 구현이
//     통과해야 할 *양성* 표준이라는 것을 보여준다.
//
// 진짜 플랫폼별 통합 테스트(KSWindowsClipboardBackend 등)는 같은
// `…Contract` 타입을 인스턴스화하고 호출 측에서 백엔드 팩토리만 갈아
// 끼우면 된다 — 윈도우 위에서 실행 가능한 환경에서.

// MARK: - Reference in-memory clipboard

// MARK: - Clipboard contract

/// Contract suite for `KSClipboardBackend`. Pass any factory closure
/// that yields a fresh, empty backend; the assertions below exercise
/// the read/write/clear/hasFormat invariants.

// MARK: - Default extension contract

/// Verifies the source-compatible defaults on the bare protocol throw
/// `unsupportedPlatform` so platforms that haven't shipped a real
/// backend don't silently succeed.

// MARK: - Shell backend default-extension contract

// MARK: - Notification backend contract

/// Records every `post` call so tests can assert the exact sequence the
/// backend received. Permission requests resolve to `true`.

actor InMemoryClipboard: KSClipboardBackend {
    private var text: String?
    private var image: Data?

    func readText() async throws(KSError) -> String? { text }

    func writeText(_ text: String) async throws(KSError) {
        self.text = text
        self.image = nil  // 한 클립보드는 한 번에 한 형식만 보유한다.
    }

    func readImage() async throws(KSError) -> Data? { image }

    func writeImage(_ image: Data) async throws(KSError) {
        self.image = image
        self.text = nil
    }

    func clear() async throws(KSError) {
        text = nil
        image = nil
    }

    func hasFormat(_ format: String) async -> Bool {
        switch format {
        case "text": return text != nil
        case "image": return image != nil
        default: return false
        }
    }
}
struct KSClipboardBackendContract {
    let make: @Sendable () async -> any KSClipboardBackend

    func runAll() async throws {
        try await emptyClipboardReadsNil()
        try await writeReadTextRoundtrip()
        try await writeImageReplacesText()
        try await clearWipesAllFormats()
        try await hasFormatReportsCurrentState()
    }

    private func emptyClipboardReadsNil() async throws {
        let cb = await make()
        let t = try await cb.readText()
        let i = try await cb.readImage()
        #expect(t == nil)
        #expect(i == nil)
    }

    private func writeReadTextRoundtrip() async throws {
        let cb = await make()
        try await cb.writeText("Hello, 世界")
        let read = try await cb.readText()
        #expect(read == "Hello, 世界")
    }

    private func writeImageReplacesText() async throws {
        let cb = await make()
        try await cb.writeText("first")
        try await cb.writeImage(Data([0x89, 0x50, 0x4E, 0x47]))
        let t = try await cb.readText()
        let i = try await cb.readImage()
        #expect(t == nil, "image write must clear text format")
        #expect(i == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    private func clearWipesAllFormats() async throws {
        let cb = await make()
        try await cb.writeText("hi")
        try await cb.clear()
        let t = try await cb.readText()
        let hasText = await cb.hasFormat("text")
        #expect(t == nil)
        #expect(hasText == false)
    }

    private func hasFormatReportsCurrentState() async throws {
        let cb = await make()
        var hasText = await cb.hasFormat("text")
        #expect(hasText == false, "fresh clipboard must report no text")
        try await cb.writeText("present")
        hasText = await cb.hasFormat("text")
        let hasUnknown = await cb.hasFormat("totally-bogus")
        #expect(hasText == true)
        #expect(hasUnknown == false, "unknown format names must yield false")
    }
}
@Suite("PAL/Clipboard contract — in-memory reference")
struct ClipboardInMemoryContractTests {
    @Test("Reference impl satisfies the contract")
    func referenceImpl() async throws {
        let contract = KSClipboardBackendContract {
            InMemoryClipboard()
        }
        try await contract.runAll()
    }
}
private struct UnimplementedClipboard: KSClipboardBackend {
    // 의도적으로 기본 익스텐션에 모든 책임을 위임한다.
}
@Suite("PAL/Clipboard contract — default extension")
struct ClipboardDefaultExtensionTests {
    @Test("Default readText throws unsupportedPlatform")
    func defaultReadThrows() async {
        let cb = UnimplementedClipboard()
        do {
            _ = try await cb.readText()
            Issue.record("expected unsupportedPlatform error")
        } catch {
            #expect(error.code == .unsupportedPlatform)
        }
    }

    @Test("Default writeText throws unsupportedPlatform")
    func defaultWriteThrows() async {
        let cb = UnimplementedClipboard()
        do {
            try await cb.writeText("x")
            Issue.record("expected unsupportedPlatform error")
        } catch {
            #expect(error.code == .unsupportedPlatform)
        }
    }

    @Test("Default hasFormat returns false for any input")
    func defaultHasFormat() async {
        let cb = UnimplementedClipboard()
        let a = await cb.hasFormat("text")
        let b = await cb.hasFormat("nonexistent")
        #expect(a == false)
        #expect(b == false)
    }
}
private struct UnimplementedShell: KSShellBackend {}
@Suite("PAL/Shell contract — default extension")
struct ShellDefaultExtensionTests {
    @Test("Default openExternal throws unsupportedPlatform")
    func openThrows() async {
        let s = UnimplementedShell()
        do {
            try await s.openExternal(URL(string: "https://example.com")!)
            Issue.record("expected unsupportedPlatform")
        } catch {
            #expect(error.code == .unsupportedPlatform)
        }
    }

    @Test("Default moveToTrash throws unsupportedPlatform")
    func trashThrows() async {
        let s = UnimplementedShell()
        do {
            try await s.moveToTrash(URL(fileURLWithPath: "/tmp/x"))
            Issue.record("expected unsupportedPlatform")
        } catch {
            #expect(error.code == .unsupportedPlatform)
        }
    }
}
actor RecordingNotificationBackend: KSNotificationBackend {
    private(set) var posted: [KSNotification] = []
    private(set) var cancelled: [String] = []
    private(set) var permissionCalls = 0

    func requestPermission() async -> Bool {
        permissionCalls += 1
        return true
    }

    func post(_ notification: KSNotification) async throws(KSError) {
        posted.append(notification)
    }

    func cancel(id: String) async {
        cancelled.append(id)
    }
}
@Suite("PAL/Notification contract — recording reference")
struct NotificationRecordingContractTests {
    @Test("post stores notifications in order")
    func postRecords() async throws {
        let backend = RecordingNotificationBackend()
        try await backend.post(KSNotification(id: "1", title: "first"))
        try await backend.post(KSNotification(id: "2", title: "second"))
        let posted = await backend.posted
        #expect(posted.count == 2)
        #expect(posted[0].id == "1")
        #expect(posted[1].id == "2")
    }

    @Test("cancel records request even without prior post")
    func cancelIndependent() async {
        let backend = RecordingNotificationBackend()
        await backend.cancel(id: "ghost")
        let cancelled = await backend.cancelled
        #expect(cancelled == ["ghost"])
    }

    @Test("requestPermission is idempotent and observable")
    func permissionIdempotent() async {
        let backend = RecordingNotificationBackend()
        let a = await backend.requestPermission()
        let b = await backend.requestPermission()
        let calls = await backend.permissionCalls
        #expect(a == true)
        #expect(b == true)
        #expect(calls == 2)
    }
}
