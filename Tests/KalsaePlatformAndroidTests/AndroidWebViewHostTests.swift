#if os(Android)
    import Testing
    import Foundation
    @testable import KalsaePlatformAndroid
    import KalsaeCore

    // MARK: - KSAndroidWebViewHost

    @Suite("KSAndroidWebViewHost — IPC scaffold")
    @MainActor
    struct KSAndroidWebViewHostTests {

        @Test("documentStartScript contains runtime source")
        func documentStartScriptContainsRuntime() async {
            let host = KSAndroidWebViewHost()
            let script = host.documentStartScript()
            #expect(script.contains("window.__KS_"))
        }

        @Test("addDocumentCreatedScript appends to documentStartScript")
        func addDocumentCreatedScript() async throws {
            let host = KSAndroidWebViewHost()
            try host.addDocumentCreatedScript("window.__KS_TEST = true;")
            let script = host.documentStartScript()
            #expect(script.contains("window.__KS_TEST = true;"))
        }

        @Test("postJSON drops frame and logs when evaluateJS hook absent")
        func postJSONDropsWhenNoBridge() async throws {
            let host = KSAndroidWebViewHost()
            // 던지지 않아야 한다 — 경고를 로깅하고 드롭한다.
            try host.postJSON("{\"kind\":\"event\"}")
        }

        @Test("postJSON calls evaluateJS hook when installed")
        func postJSONCallsHook() async throws {
            let host = KSAndroidWebViewHost()
            var called: String? = nil
            host.onEvaluateJS = { called = $0 }
            try host.postJSON("{\"kind\":\"event\"}")
            #expect(called?.contains("__KS_receive") == true)
        }

        @Test("navigate stores pending URL when onLoadURL absent")
        func navigateStoresPending() async throws {
            let host = KSAndroidWebViewHost()
            try host.navigate(url: "https://example.com")
            // onLoadURL이 없으면 flushPendingURL은 아무 작업도 하지 않는다 — 크래시 없음.
            host.flushPendingURL()
        }

        @Test("navigate calls onLoadURL when installed")
        func navigateCallsHook() async throws {
            let host = KSAndroidWebViewHost()
            var loaded: String? = nil
            host.onLoadURL = { loaded = $0 }
            try host.navigate(url: "https://kalsae.test/")
            #expect(loaded == "https://kalsae.test/")
        }
    }
#endif
