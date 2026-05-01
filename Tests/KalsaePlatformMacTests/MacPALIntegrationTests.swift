#if os(macOS)
import Testing
import Foundation
@testable import KalsaePlatformMac
import KalsaeCore

// MARK: - KSMacPlatform 초기화 검증
//
// 플랫폼 이니셜라이저가 올바른 백엔드 타입을 배선하고
// commandRegistry를 공유하는지 확인한다.

@Suite("KSMacPlatform — init & backend wiring")
struct KSMacPlatformInitTests {

    /// 각 `var` 프로퍼티가 올바른 구체 타입을 반환해야 한다.
    @Test("All PAL backend properties return correct concrete types")
    func backendTypesAreCorrect() {
        let platform = KSMacPlatform()
        #expect(platform.windows is KSMacWindowBackend)
        #expect(platform.dialogs is KSMacDialogBackend)
        #expect((platform.tray as? KSMacTrayBackend) != nil)
        #expect(platform.menus is KSMacMenuBackend)
        #expect(platform.notifications is KSMacNotificationBackend)
        #expect((platform.shell as? KSMacShellBackend) != nil)
        #expect((platform.clipboard as? KSMacClipboardBackend) != nil)
    }

    /// `commandRegistry`에 커맨드를 등록한 뒤 같은 레지스트리로
    /// dispatch해 반환값이 일치함을 확인 — 레지스트리가 올바로
    /// 배선됐다는 행위적 증거.
    @Test("commandRegistry wiring — register and dispatch round-trip")
    func commandRegistryRoundTrip() async {
        let platform = KSMacPlatform()
        let registry = platform.commandRegistry
        await registry.register("ks.test.echo") { data in .success(data) }

        let payload = Data("hello-macos".utf8)
        let result = await registry.dispatch(name: "ks.test.echo", args: payload)
        switch result {
        case .success(let d):
            #expect(d == payload)
        case .failure(let e):
            Issue.record("Echo command must succeed: \(e)")
        }
    }
}

// MARK: - KSMacWindowBackend 유닛 계약
//
// 잘못된 핸들 / 빈 레지스트리 상태에 대한 에러 코드를 검증한다.

@Suite("KSMacWindowBackend — unit contract (no NSWindow)")
struct KSMacWindowBackendUnitTests {

    let backend = KSMacWindowBackend()

    /// 존재하지 않는 핸들로 `webView(for:)`를 호출하면
    /// `windowCreationFailed` 에러가 나와야 한다.
    @Test("webView(for:) throws windowCreationFailed for unknown handle")
    func webViewForMissingHandle() async {
        let handle = KSWindowHandle(label: "ks-test-mac-ghost-wv", rawValue: 0)
        do {
            _ = try await backend.webView(for: handle)
            Issue.record("Expected windowCreationFailed to be thrown")
        } catch let e {
            #expect(e.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(e.code)")
        }
    }

    /// 존재하지 않는 핸들로 `show()`를 호출하면
    /// `windowCreationFailed` 에러가 나와야 한다.
    @Test("show() throws windowCreationFailed for unknown handle")
    func showMissingHandle() async {
        let handle = KSWindowHandle(label: "ks-test-mac-ghost-show", rawValue: 0)
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
            label: "ks-test-mac-nonexistent-\(UInt64.random(in: 1...UInt64.max))")
        #expect(result == nil)
    }
}

// MARK: - KSMacHandleRegistry 직접 검증
//
// `KSMacHandleRegistry`는 레이블/rawValue 양방향 조회를 지원한다.
// `@testable import` 로 internal 타입에 접근한다.

@Suite("KSMacHandleRegistry — direct registry contract", .serialized)
@MainActor
struct KSMacHandleRegistryTests {

    private func makeWindow() throws -> KSMacWindow {
        KSMacApp.shared.ensureInitialized()
        return try KSMacWindow(config: KSWindowConfig(
            label: "ks-test-mac-reg-\(UUID().uuidString.prefix(8).lowercased())",
            title: "KS Registry Test",
            width: 320,
            height: 240,
            visible: false
        ))
    }

    /// `register` 후 `handle(for:)`이 레이블과 rawValue를 정확히 반환해야 한다.
    @Test("register then handle(for:) returns matching handle")
    func registerThenFind() throws {
        let window = try makeWindow()
        let label = window.config.label
        let raw = UInt64(UInt(bitPattern: ObjectIdentifier(window)))
        KSMacHandleRegistry.shared.register(label: label, rawValue: raw, window: window)
        defer { KSMacHandleRegistry.shared.unregister(label: label) }

        let handle = KSMacHandleRegistry.shared.handle(for: label)
        #expect(handle != nil)
        #expect(handle?.label == label)
    }

    /// `unregister` 후 `allWindows()`에서 제거돼야 한다.
    @Test("unregister removes window from allWindows()")
    func unregisterRemovesFromAllWindows() throws {
        let window = try makeWindow()
        let label = window.config.label
        let raw = UInt64(UInt(bitPattern: ObjectIdentifier(window)))
        KSMacHandleRegistry.shared.register(label: label, rawValue: raw, window: window)

        KSMacHandleRegistry.shared.unregister(label: label)
        let all = KSMacHandleRegistry.shared.allWindows()
        #expect(!all.contains { $0 === window })
    }

    /// `unregister` 후 `window(for:)`이 `nil`을 반환해야 한다.
    @Test("window(for:) returns nil after unregister")
    func windowForNilAfterUnregister() throws {
        let window = try makeWindow()
        let label = window.config.label
        let raw = UInt64(UInt(bitPattern: ObjectIdentifier(window)))
        let handle = KSWindowHandle(label: label, rawValue: raw)
        KSMacHandleRegistry.shared.register(label: label, rawValue: raw, window: window)

        KSMacHandleRegistry.shared.unregister(label: label)
        let found = KSMacHandleRegistry.shared.window(for: handle)
        #expect(found == nil)
    }
}

// MARK: - KSMacWindowBackend.create() 계약 테스트

@Suite("KSMacWindowBackend — create() contract", .serialized)
@MainActor
struct KSMacWindowBackendCreateTests {

    private func makeConfig() -> KSWindowConfig {
        KSWindowConfig(
            label: "ks-test-mac-be-\(UUID().uuidString.prefix(8).lowercased())",
            title: "KS Mac Backend Test",
            width: 400,
            height: 300,
            visible: false
        )
    }

    private func setUp() {
        KSMacApp.shared.ensureInitialized()
    }

    /// `create()` 성공 시 핸들의 레이블이 config.label과 일치해야 한다.
    @Test("create() — handle label matches config.label")
    func createHandleLabelMatchesConfig() async {
        setUp()
        let backend = KSMacWindowBackend()
        let config = makeConfig()

        do {
            let handle = try await backend.create(config)
            defer { Task { try? await backend.close(handle) } }
            #expect(handle.label == config.label)
        } catch let e {
            Issue.record("create() failed unexpectedly: \(e)")
        }
    }

    /// `create()` 성공 시 rawValue가 0이 아니어야 한다.
    @Test("create() — rawValue is non-zero")
    func createHandleRawValueNonZero() async {
        setUp()
        let backend = KSMacWindowBackend()
        let config = makeConfig()

        do {
            let handle = try await backend.create(config)
            defer { Task { try? await backend.close(handle) } }
            #expect(handle.rawValue != 0)
        } catch let e {
            Issue.record("create() failed unexpectedly: \(e)")
        }
    }

    /// `create()` 성공 시 `all()`에 해당 창이 포함돼야 한다.
    @Test("create() — window appears in all() after successful init")
    func createAppearsInAll() async {
        setUp()
        let backend = KSMacWindowBackend()
        let config = makeConfig()

        do {
            let handle = try await backend.create(config)
            let all = await backend.all()
            try? await backend.close(handle)
            #expect(all.contains { $0.label == config.label })
        } catch let e {
            Issue.record("create() failed unexpectedly: \(e)")
        }
    }

    /// `create()` 성공 시 `webView(for:)`가 `KSWebViewBackend`를 반환해야 한다.
    @Test("create() — webView(for:) returns KSWebViewBackend")
    func createWebViewReturnsBackend() async {
        setUp()
        let backend = KSMacWindowBackend()
        let config = makeConfig()

        do {
            let handle = try await backend.create(config)
            let webview = try await backend.webView(for: handle)
            try? await backend.close(handle)
            // 반환된 existential은 절대 nil이 아니다.
            _ = webview
        } catch let e {
            Issue.record("create() or webView(for:) failed unexpectedly: \(e)")
        }
    }
}

// MARK: - KSMacWindowBackend.webView(for:) + close() 계약 테스트

@Suite("KSMacWindowBackend — webView(for:) contract", .serialized)
@MainActor
struct KSMacWindowBackendWebViewTests {

    private func makeConfig() -> KSWindowConfig {
        KSWindowConfig(
            label: "ks-test-mac-wv-\(UUID().uuidString.prefix(8).lowercased())",
            title: "KS Mac WebView Test",
            width: 400,
            height: 300,
            visible: false
        )
    }

    private func setUp() {
        KSMacApp.shared.ensureInitialized()
    }

    /// `close()` 후 `webView(for:)`는 `windowCreationFailed`를 던져야 한다.
    @Test("webView(for:) throws windowCreationFailed after close()")
    func webViewThrowsAfterClose() async {
        setUp()
        let backend = KSMacWindowBackend()
        let config = makeConfig()

        do {
            let handle = try await backend.create(config)
            try await backend.close(handle)

            do {
                _ = try await backend.webView(for: handle)
                Issue.record("Expected windowCreationFailed after close()")
            } catch let e {
                #expect(e.code == .windowCreationFailed,
                        "Got \(e.code), expected windowCreationFailed")
            }
        } catch let e {
            Issue.record("create() failed unexpectedly: \(e)")
        }
    }

    /// `close()` 후 `find(label:)`은 `nil`을 반환해야 한다.
    @Test("find(label:) returns nil after close()")
    func findNilAfterClose() async {
        setUp()
        let backend = KSMacWindowBackend()
        let config = makeConfig()

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
#endif
