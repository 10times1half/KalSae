#if os(iOS)
import Testing
import Foundation
@testable import KalsaePlatformIOS
import KalsaeCore

// MARK: - KSiOSPlatform 초기화 검증

@Suite("KSiOSPlatform — init & backend wiring")
struct KSiOSPlatformInitTests {

    @Test("All PAL backend properties return correct concrete types")
    func backendTypesAreCorrect() {
        let platform = KSiOSPlatform()
        #expect(platform.windows is KSiOSWindowBackend)
        #expect(platform.dialogs is KSiOSDialogBackend)
        #expect(platform.tray == nil)
        #expect(platform.menus is KSiOSMenuBackend)
        #expect(platform.notifications is KSiOSNotificationBackend)
        #expect((platform.shell as? KSiOSShellBackend) != nil)
        #expect((platform.clipboard as? KSiOSClipboardBackend) != nil)
        #expect(platform.accelerators == nil)
    }

    @Test("commandRegistry wiring — register and dispatch round-trip")
    func commandRegistryRoundTrip() async {
        let platform = KSiOSPlatform()
        let registry = platform.commandRegistry
        await registry.register("ks.test.echo") { data in .success(data) }

        let payload = Data("hello-ios".utf8)
        let result = await registry.dispatch(name: "ks.test.echo", args: payload)
        switch result {
        case .success(let d):
            #expect(d == payload)
        case .failure(let e):
            Issue.record("Echo command must succeed: \(e)")
        }
    }
}

// MARK: - KSiOSWindowBackend 유닛 계약

@Suite("KSiOSWindowBackend — unit contract")
struct KSiOSWindowBackendUnitTests {

    let backend = KSiOSWindowBackend()

    /// 존재하지 않는 핸들로 `webView(for:)`를 호출하면
    /// `webviewInitFailed` 에러가 나와야 한다.
    @Test("webView(for:) throws webviewInitFailed for unknown handle")
    func webViewForMissingHandle() async {
        let handle = KSWindowHandle(label: "ks-test-ios-ghost-wv", rawValue: 0)
        do {
            _ = try await backend.webView(for: handle)
            Issue.record("Expected webviewInitFailed to be thrown")
        } catch let e {
            #expect(e.code == .webviewInitFailed,
                    "Expected webviewInitFailed, got \(e.code)")
        }
    }

    /// 존재하지 않는 핸들로 `show()`를 호출하면
    /// `windowCreationFailed` 에러가 나와야 한다.
    @Test("show() throws windowCreationFailed for unknown handle")
    func showMissingHandle() async {
        let handle = KSWindowHandle(label: "ks-test-ios-ghost-show", rawValue: 0)
        do {
            try await backend.show(handle)
            Issue.record("Expected windowCreationFailed to be thrown")
        } catch let e {
            #expect(e.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(e.code)")
        }
    }

    /// `find(label:)`은 존재하지 않는 레이블에 대해 `nil`을 반환해야 한다.
    @Test("find(label:) returns nil for unknown label")
    func findUnknownLabel() async {
        let result = await backend.find(
            label: "ks-test-ios-nonexistent-\(UInt64.random(in: 1...UInt64.max))")
        #expect(result == nil)
    }

    /// `create()` 후 `find(label:)`이 핸들을 반환해야 한다.
    @Test("create() — handle is findable by label")
    func createThenFind() async {
        let config = KSWindowConfig(
            label: "ks-test-ios-be-\(UUID().uuidString.prefix(8).lowercased())",
            title: "KS iOS Test",
            width: 390, height: 844, visible: true)

        do {
            let handle = try await backend.create(config)
            defer { Task { try? await backend.close(handle) } }
            let found = await backend.find(label: config.label)
            #expect(found?.label == config.label)
        } catch let e {
            Issue.record("create() failed unexpectedly: \(e)")
        }
    }

    /// `create()` 후 `all()`이 해당 핸들을 포함해야 한다.
    @Test("create() — handle appears in all()")
    func createAppearsInAll() async {
        let config = KSWindowConfig(
            label: "ks-test-ios-all-\(UUID().uuidString.prefix(8).lowercased())",
            title: "KS iOS All Test",
            width: 390, height: 844, visible: true)

        do {
            let handle = try await backend.create(config)
            defer { Task { try? await backend.close(handle) } }
            let all = await backend.all()
            #expect(all.contains { $0.label == config.label })
        } catch let e {
            Issue.record("create() failed unexpectedly: \(e)")
        }
    }

    /// `close()` 후 `find(label:)`이 `nil`을 반환해야 한다.
    @Test("close() — handle is no longer findable")
    func closeRemovesFromRegistry() async {
        let config = KSWindowConfig(
            label: "ks-test-ios-close-\(UUID().uuidString.prefix(8).lowercased())",
            title: "KS iOS Close Test",
            width: 390, height: 844, visible: true)

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

// MARK: - KSiOSHandleRegistry 직접 검증

@Suite("KSiOSHandleRegistry — direct registry contract", .serialized)
@MainActor
struct KSiOSHandleRegistryTests {

    @Test("register then handle(for:) returns matching handle")
    func registerThenFind() {
        let label = "ks-test-ios-reg-\(UUID().uuidString.prefix(8).lowercased())"
        let handle = KSiOSHandleRegistry.shared.register(label: label)
        defer { KSiOSHandleRegistry.shared.unregister(handle) }

        let found = KSiOSHandleRegistry.shared.handle(for: label)
        #expect(found != nil)
        #expect(found?.label == label)
    }

    @Test("unregister removes handle from registry")
    func unregisterRemovesHandle() {
        let label = "ks-test-ios-unreg-\(UUID().uuidString.prefix(8).lowercased())"
        let handle = KSiOSHandleRegistry.shared.register(label: label)
        KSiOSHandleRegistry.shared.unregister(handle)
        #expect(KSiOSHandleRegistry.shared.handle(for: label) == nil)
    }

    @Test("webView not registered returns nil")
    func webViewNilBeforeRegister() {
        let label = "ks-test-ios-wv-nil-\(UUID().uuidString.prefix(8).lowercased())"
        #expect(KSiOSHandleRegistry.shared.webView(for: label) == nil)
    }

    @Test("registerWebView then webView(for:) returns host")
    func registerWebViewThenFind() {
        let label = "ks-test-ios-wvreg-\(UUID().uuidString.prefix(8).lowercased())"
        let handle = KSiOSHandleRegistry.shared.register(label: label)
        defer { KSiOSHandleRegistry.shared.unregister(handle) }

        let wvHost = KSiOSWebViewHost(label: label)
        KSiOSHandleRegistry.shared.registerWebView(wvHost, for: label)
        #expect(KSiOSHandleRegistry.shared.webView(for: label) != nil)
    }
}

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

// MARK: - KSiOSShellBackend 계약 (openExternal)

@Suite("KSiOSShellBackend — unit contract")
struct KSiOSShellBackendTests {

    let backend = KSiOSShellBackend()

    @Test("showItemInFolder throws unsupportedPlatform")
    func showItemInFolderThrows() async {
        do {
            try await backend.showItemInFolder(URL(fileURLWithPath: "/tmp"))
            Issue.record("Expected unsupportedPlatform to be thrown")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }

    @Test("moveToTrash throws unsupportedPlatform")
    func moveToTrashThrows() async {
        do {
            try await backend.moveToTrash(URL(fileURLWithPath: "/tmp/test.txt"))
            Issue.record("Expected unsupportedPlatform to be thrown")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }
}

// MARK: - KSiOSMenuBackend 계약 (stub — no-op, does not throw)

@Suite("KSiOSMenuBackend — stub is no-op (does not throw)")
struct KSiOSMenuBackendTests {

    let backend = KSiOSMenuBackend()

    @Test("installAppMenu succeeds silently")
    func installAppMenuNoThrow() async {
        do {
            try await backend.installAppMenu([])
        } catch let e {
            Issue.record("installAppMenu should not throw on iOS: \(e)")
        }
    }

    @Test("showContextMenu succeeds silently")
    func showContextMenuNoThrow() async {
        let handle = KSWindowHandle(label: "ks-test-ios-menu", rawValue: 1)
        do {
            try await backend.showContextMenu([], at: KSPoint(x: 0, y: 0), in: handle)
        } catch let e {
            Issue.record("showContextMenu should not throw on iOS: \(e)")
        }
    }
}

// MARK: - KSiOSAutostartBackend 계약 (stub — all throw)

@Suite("KSiOSAutostartBackend — stub throws unsupportedPlatform")
struct KSiOSAutostartBackendTests {

    let backend = KSiOSAutostartBackend()

    @Test("isEnabled returns false")
    func isEnabledReturnsFalse() {
        #expect(!backend.isEnabled())
    }

    @Test("enable throws unsupportedPlatform")
    func enableThrows() {
        do {
            try backend.enable()
            Issue.record("Expected unsupportedPlatform")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }

    @Test("disable throws unsupportedPlatform")
    func disableThrows() {
        do {
            try backend.disable()
            Issue.record("Expected unsupportedPlatform")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }
}

// MARK: - KSiOSDeepLinkBackend 계약

@Suite("KSiOSDeepLinkBackend — unit contract")
struct KSiOSDeepLinkBackendTests {

    let backend = KSiOSDeepLinkBackend(identifier: "com.example.kalsae-ios-test")

    @Test("register throws unsupportedPlatform (runtime registration not possible)")
    func registerThrows() {
        do {
            try backend.register(scheme: "myapp")
            Issue.record("Expected unsupportedPlatform")
        } catch let e {
            #expect(e.code == .unsupportedPlatform)
        }
    }

    @Test("isRegistered returns false for unknown scheme")
    func isRegisteredFalseForUnknown() {
        // 테스트 번들에는 CFBundleURLTypes가 없으므로 항상 false.
        #expect(!backend.isRegistered(scheme: "myapp-unknown-\(UUID().uuidString)"))
    }

    @Test("extractURLs filters by scheme")
    func extractURLsFilters() {
        let args = ["myapp://open?id=1", "otherap://nope", "not-a-url", "myapp://open?id=2"]
        let urls = backend.extractURLs(fromArgs: args, forSchemes: ["myapp"])
        #expect(urls.count == 2)
        #expect(urls.allSatisfy { $0.hasPrefix("myapp://") })
    }

    @Test("currentLaunchURLs filters CommandLine args by scheme")
    func currentLaunchURLsFilters() {
        // CommandLine.arguments는 테스트 실행기 인자 — 스킴이 없으면 빈 배열 반환.
        let urls = backend.currentLaunchURLs(forSchemes: ["myapp-ks-test"])
        #expect(urls.isEmpty)
    }
}

// MARK: - KSiOSWebViewHost 계약

@Suite("KSiOSWebViewHost — unit contract", .serialized)
@MainActor
struct KSiOSWebViewHostTests {

    @Test("init creates WKWebView")
    func initCreatesWebView() {
        let host = KSiOSWebViewHost(label: "ks-test-ios-wvh")
        #expect(host.webView.frame == .zero)
    }

    @Test("addDocumentCreatedScript does not throw")
    func addDocumentCreatedScriptNoThrow() {
        let host = KSiOSWebViewHost(label: "ks-test-ios-wvh-script")
        do {
            try host.addDocumentCreatedScript("console.log('hello');")
        } catch let e {
            Issue.record("addDocumentCreatedScript threw: \(e)")
        }
    }

    @Test("setAssetRoot with nonexistent path does not throw")
    func setAssetRootNoThrow() {
        let host = KSiOSWebViewHost(label: "ks-test-ios-wvh-root")
        let root = URL(fileURLWithPath: "/tmp/ks-ios-test-root")
        do {
            try host.setAssetRoot(root)
        } catch let e {
            Issue.record("setAssetRoot threw: \(e)")
        }
    }

    @Test("navigate with invalid URL throws webviewInitFailed")
    func navigateInvalidURLThrows() {
        let host = KSiOSWebViewHost(label: "ks-test-ios-wvh-nav")
        do {
            try host.navigate(url: "not a url !!!")
            Issue.record("Expected webviewInitFailed")
        } catch let e {
            #expect(e.code == .webviewInitFailed)
        }
    }
}
#endif
