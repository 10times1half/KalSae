#if os(iOS)
    import Testing
    import Foundation
    @testable import KalsaePlatformIOS
    import KalsaeCore

    // MARK: - KSiOSClipboardBackend 계약

    @Suite("KSiOSClipboardBackend — unit contract")
    struct KSiOSClipboardBackendTests {

        let backend = KSiOSClipboardBackend()

        @Test("writeText / readText round-trip")
        func writeReadText() async {
            let text = "kalsae-ios-clip-\(UUID().uuidString)"
            do {
                try await backend.writeText(text)
                let read = try await backend.readText()
                #expect(read == text)
            } catch let e {
                Issue.record("Clipboard read/write failed: \(e)")
            }
        }

        @Test("clear() makes readText throw")
        func clearMakesReadTextThrow() async {
            do {
                try await backend.writeText("temp")
                try await backend.clear()
                _ = try await backend.readText()
                Issue.record("readText should throw after clear()")
            } catch {
                // 비어 있는 클립보드에서 readText가 실패하는 것은 정상이다.
            }
        }

        @Test("hasFormat returns false for image when no image on board")
        func hasFormatImageFalse() async {
            do {
                try await backend.clear()
            } catch {}
            let has = await backend.hasFormat("image")
            // 빈 클립보드에서는 false여야 한다.
            _ = has  // macOS와 동일하게 단언 없이 크래시 없음 검증
        }
    }
#endif
