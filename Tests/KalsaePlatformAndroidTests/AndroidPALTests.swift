#if os(Android)
import Testing
import Foundation
@testable import KalsaePlatformAndroid
import KalsaeCore

// MARK: - KSAndroidPlatform 초기화 검증

@Suite("KSAndroidPlatform — init & backend wiring")
struct KSAndroidPlatformInitTests {

    @Test("All PAL backend properties return correct concrete types")
    func backendTypesAreCorrect() {
        let platform = KSAndroidPlatform()
        #expect(platform.windows is KSAndroidWindowBackend)
        #expect(platform.dialogs is KSAndroidDialogBackend)
        #expect(platform.tray == nil)
        #expect(platform.menus is KSAndroidMenuBackend)
        #expect(platform.notifications is KSAndroidNotificationBackend)
        #expect((platform.shell as? KSAndroidShellBackend) != nil)
        #expect((platform.clipboard as? KSAndroidClipboardBackend) != nil)
        #expect(platform.accelerators == nil)
    }

    @Test("commandRegistry wiring — register and dispatch round-trip")
    func commandRegistryRoundTrip() async {
        let platform = KSAndroidPlatform()
        let registry = platform.commandRegistry
        await registry.register("ks.test.echo") { data in .success(data) }

        let payload = Data("hello-android".utf8)
        let result = await registry.dispatch(name: "ks.test.echo", args: payload)
        switch result {
        case .success(let d):
            #expect(d == payload)
        case .failure(let e):
            Issue.record("Echo command must succeed: \(e)")
        }
    }
}

// MARK: - KSAndroidWindowBackend 유닛 계약

@Suite("KSAndroidWindowBackend — unit contract")
struct KSAndroidWindowBackendUnitTests {

    let backend = KSAndroidWindowBackend()

    @Test("webView(for:) throws webviewInitFailed for unknown handle")
    func webViewForMissingHandle() async {
        let handle = KSWindowHandle(label: "ks-test-android-ghost-wv", rawValue: 0)
        do {
            _ = try await backend.webView(for: handle)
            Issue.record("Expected webviewInitFailed to be thrown")
        } catch let e {
            #expect(e.code == .webviewInitFailed,
                    "Expected webviewInitFailed, got \(e.code)")
        }
    }

    @Test("show() throws windowCreationFailed for unknown handle")
    func showMissingHandle() async {
        let handle = KSWindowHandle(label: "ks-test-android-ghost-show", rawValue: 0)
        do {
            try await backend.show(handle)
            Issue.record("Expected windowCreationFailed to be thrown")
        } catch let e {
            #expect(e.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(e.code)")
        }
    }

    @Test("find(label:) returns nil for unknown label")
    func findUnknownLabel() async {
        let result = await backend.find(
            label: "ks-test-android-nonexistent-\(UInt64.random(in: 1...UInt64.max))")
        #expect(result == nil)
    }

    @Test("create() — handle is findable by label")
    func createThenFind() async {
        let config = KSWindowConfig(
            label: "ks-test-android-be-\(UUID().uuidString.prefix(8).lowercased())",
            title: "KS Android Test",
            width: 360, height: 800, visible: true)

        do {
            let handle = try await backend.create(config)
            defer { Task { try? await backend.close(handle) } }
            let found = await backend.find(label: config.label)
            #expect(found?.label == config.label)
        } catch let e {
            Issue.record("create() failed unexpectedly: \(e)")
        }
    }

    @Test("create() — handle appears in all()")
    func createAppearsInAll() async {
        let config = KSWindowConfig(
            label: "ks-test-android-all-\(UUID().uuidString.prefix(8).lowercased())",
            title: "KS Android All Test",
            width: 360, height: 800, visible: true)

        do {
            let handle = try await backend.create(config)
            defer { Task { try? await backend.close(handle) } }
            let all = await backend.all()
            #expect(all.contains { $0.label == config.label })
        } catch let e {
            Issue.record("create() failed unexpectedly: \(e)")
        }
    }

    @Test("close() — handle is no longer findable")
    func closeRemovesFromRegistry() async {
        let config = KSWindowConfig(
            label: "ks-test-android-close-\(UUID().uuidString.prefix(8).lowercased())",
            title: "KS Android Close Test",
            width: 360, height: 800, visible: true)

        do {
            let handle = try await backend.create(config)
            try await backend.close(handle)
            let found = await backend.find(label: config.label)
            #expect(found == nil)
        } catch let e {
            Issue.record("Unexpected error: \(e)")
        }
    }
}

// MARK: - Unsupported backends: error code 확인

@Suite("KSAndroidPlatform — unsupported backend error codes")
struct KSAndroidUnsupportedTests {

    @Test("KSAndroidDialogBackend.openFile throws unsupportedPlatform")
    func dialogOpenFileThrows() async {
        let backend = KSAndroidDialogBackend()
        do {
            _ = try await backend.openFile(options: KSOpenFileOptions(), parent: nil)
            Issue.record("Expected unsupportedPlatform")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }

    @Test("KSAndroidMenuBackend.installAppMenu throws unsupportedPlatform")
    func menuInstallAppMenuThrows() async {
        let backend = KSAndroidMenuBackend()
        do {
            try await backend.installAppMenu([])
            Issue.record("Expected unsupportedPlatform")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }

    @Test("KSAndroidShellBackend.openExternal throws when bridge absent")
    func shellOpenExternalThrowsNoBridge() async {
        let backend = KSAndroidShellBackend()
        do {
            try await backend.openExternal(URL(string: "https://example.com")!)
            Issue.record("Expected unsupportedPlatform")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }

    @Test("KSAndroidShellBackend.moveToTrash throws unsupportedPlatform")
    func shellMoveToTrashThrows() async {
        let backend = KSAndroidShellBackend()
        do {
            try await backend.moveToTrash(URL(string: "file:///tmp/foo")!)
            Issue.record("Expected unsupportedPlatform")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }
}

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
        backend.onReadText  = { stored }
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

// MARK: - KSAndroidDeepLinkBackend

@Suite("KSAndroidDeepLinkBackend — URL extraction")
struct KSAndroidDeepLinkBackendTests {

    @Test("register throws unsupportedPlatform")
    func registerThrows() {
        let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
        do {
            try backend.register(scheme: "myapp")
            Issue.record("Expected unsupportedPlatform")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }

    @Test("unregister throws unsupportedPlatform")
    func unregisterThrows() {
        let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
        do {
            try backend.unregister(scheme: "myapp")
            Issue.record("Expected unsupportedPlatform")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }

    @Test("extractURLs returns matching scheme URLs")
    func extractURLs() {
        let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
        let args = ["myapp://open?id=1", "https://example.com", "other://foo", "notaurl"]
        let result = backend.extractURLs(fromArgs: args, forSchemes: ["myapp"])
        #expect(result == ["myapp://open?id=1"])
    }

    @Test("extractURLs is case-insensitive on scheme")
    func extractURLsCaseInsensitive() {
        let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
        let args = ["MYAPP://open?id=2"]
        let result = backend.extractURLs(fromArgs: args, forSchemes: ["myapp"])
        #expect(result == ["MYAPP://open?id=2"])
    }

    @Test("isRegistered returns false without knownSchemes populated")
    func isRegisteredFalse() {
        KSAndroidDeepLinkBackend.knownSchemes = []
        let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
        #expect(backend.isRegistered(scheme: "myapp") == false)
    }

    @Test("isRegistered returns true when knownSchemes populated")
    func isRegisteredTrue() {
        KSAndroidDeepLinkBackend.knownSchemes = ["myapp"]
        let backend = KSAndroidDeepLinkBackend(identifier: "com.test.app")
        let result = backend.isRegistered(scheme: "myapp")
        // 재설정
        KSAndroidDeepLinkBackend.knownSchemes = []
        #expect(result == true)
    }
}

// MARK: - KSAndroidPermissions

@Suite("KSAndroidPermissions — state registry")
struct KSAndroidPermissionsTests {

    @Test("default state is notDetermined")
    func defaultState() {
        let perms = KSAndroidPermissions()
        #expect(perms.state(for: "POST_NOTIFICATIONS") == .notDetermined)
    }

    @Test("setState / state round-trip")
    func roundTrip() {
        let perms = KSAndroidPermissions()
        perms.setState(.granted, for: "POST_NOTIFICATIONS")
        #expect(perms.state(for: "POST_NOTIFICATIONS") == .granted)
        #expect(perms.isGranted("POST_NOTIFICATIONS") == true)
    }

    @Test("isGranted returns false when denied")
    func isGrantedFalseWhenDenied() {
        let perms = KSAndroidPermissions()
        perms.setState(.denied, for: "POST_NOTIFICATIONS")
        #expect(perms.isGranted("POST_NOTIFICATIONS") == false)
    }
}

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
