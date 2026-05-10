#if os(Android)
    import Testing
    import Foundation
    @testable import KalsaePlatformAndroid
    import KalsaeCore

    // MARK: - KSAndroidClipboardBackend

    @Suite("KSAndroidClipboardBackend — injection hook contract")
    struct KSAndroidClipboardBackendTests {

        @Test("readText throws when bridge not installed")
        func readTextNoBridge() async {
            let backend = KSAndroidClipboardBackend()
            do {
                _ = try await backend.readText()
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("writeText throws when bridge not installed")
        func writeTextNoBridge() async {
            let backend = KSAndroidClipboardBackend()
            do {
                try await backend.writeText("hello")
                Issue.record("Expected unsupportedPlatform")
            } catch let e {
                #expect(e.code == .unsupportedPlatform)
            }
        }

        @Test("readText / writeText round-trip when hooks installed")
        func roundTripWithHooks() async {
            let backend = KSAndroidClipboardBackend()
            var stored: String? = nil
            backend.onReadText = { stored }
            backend.onWriteText = { stored = $0 }

            do {
                try await backend.writeText("android-test")
                let result = try await backend.readText()
                #expect(result == "android-test")
            } catch let e {
                Issue.record("Unexpected error: \(e)")
            }
        }

        @Test("hasFormat('text') returns false when hook absent")
        func hasFormatFalseNoBridge() async {
            let backend = KSAndroidClipboardBackend()
            let result = await backend.hasFormat("text")
            #expect(result == false)
        }

        @Test("hasFormat('text') returns true when hook says yes")
        func hasFormatTrueWithHook() async {
            let backend = KSAndroidClipboardBackend()
            backend.onHasText = { true }
            let result = await backend.hasFormat("text")
            #expect(result == true)
        }
    }
#endif
