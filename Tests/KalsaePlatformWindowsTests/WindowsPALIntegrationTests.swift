#if os(Windows)
    import Testing
    import Foundation
    import WinSDK
    @testable import KalsaePlatformWindows
    import KalsaeCore

    // MARK: - KSWindowsPlatform 초기화 검증
    //
    // 플랫폼 이니셜라이저가 올바른 백엔드 타입을 배선하고
    // commandRegistry를 공유하는지 확인한다.

    @Suite("KSWindowsPlatform — init & backend wiring")
    struct KSWindowsPlatformInitTests {

        /// 각 `var` 프로퍼티가 올바른 구체 타입을 반환해야 한다.
        @Test("All PAL backend properties return correct concrete types")
        func backendTypesAreCorrect() {
            let platform = KSWindowsPlatform()
            #expect(platform.windows is KSWindowsWindowBackend)
            #expect(platform.dialogs is KSWindowsDialogBackend)
            #expect(platform.menus is KSWindowsMenuBackend)
            #expect((platform.tray as? KSWindowsTrayBackend) != nil)
            #expect((platform.shell as? KSWindowsShellBackend) != nil)
            #expect((platform.clipboard as? KSWindowsClipboardBackend) != nil)
            #expect((platform.accelerators as? KSWindowsAcceleratorBackend) != nil)
        }

        /// `commandRegistry`에 커맨드를 등록한 뒤 같은 레지스트리로
        /// dispatch해 반환값이 일치함을 확인 — 레지스트리가 올바로
        /// 배선됐다는 행위적 증거.
        @Test("commandRegistry wiring — register and dispatch round-trip")
        func commandRegistryRoundTrip() async {
            let platform = KSWindowsPlatform()
            let registry = platform.commandRegistry
            await registry.register("ks.test.echo") { data in .success(data) }

            let payload = Data("hello-windows".utf8)
            let result = await registry.dispatch(name: "ks.test.echo", args: payload)
            switch result {
            case .success(let d):
                #expect(d == payload)
            case .failure(let e):
                Issue.record("Echo command must succeed: \(e)")
            }
        }
    }

    // MARK: - KSWindowsWindowBackend 유닛 계약
    //
    // 실제 Win32 창을 만들지 않고 잘못된 핸들 / 빈 레지스트리 상태에
    // 대한 에러 코드를 검증한다.

    @Suite("KSWindowsWindowBackend — unit contract (no Win32 window)")
    struct KSWindowsWindowBackendUnitTests {

        let backend = KSWindowsWindowBackend()

        /// 존재하지 않는 핸들로 `webView(for:)`를 호출하면
        /// `windowCreationFailed` 에러가 나와야 한다.
        @Test("webView(for:) throws windowCreationFailed for unknown handle")
        func webViewForMissingHandle() async {
            let handle = KSWindowHandle(label: "ks-test-ghost-wv", rawValue: 0)
            do {
                _ = try await backend.webView(for: handle)
                Issue.record("Expected windowCreationFailed to be thrown")
            } catch let e {
                #expect(
                    e.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(e.code)")
            }
        }

        /// 존재하지 않는 핸들로 `show()`를 호출하면
        /// `windowCreationFailed` 에러가 나와야 한다.
        @Test("show() throws windowCreationFailed for unknown handle")
        func showMissingHandle() async {
            let handle = KSWindowHandle(label: "ks-test-ghost-show", rawValue: 0)
            do {
                try await backend.show(handle)
                Issue.record("Expected windowCreationFailed to be thrown")
            } catch let e {
                #expect(
                    e.code == .windowCreationFailed,
                    "Expected windowCreationFailed, got \(e.code)")
            }
        }

        /// `find(label:)`은 존재하지 않는 레이블에 대해 `nil`을 반환해야 한다.
        @Test("find(label:) returns nil for unknown label")
        func findUnknownLabel() async {
            let result = await backend.find(label: "ks-test-nonexistent-xyz-\(UInt64.random(in: 1...UInt64.max))")
            #expect(result == nil)
        }
    }

    // MARK: - Win32Window 직접 통합 테스트
    //
    // WebView2 없이 Win32 창 생성·등록·해제만 검증한다.
    // `Win32Window`는 internal 타입이므로 `@testable import` 를 통해 접근한다.
    // 이 검증 스위트는 `KSWindowsWindowBackend.create()` 에서 WebView2 초기화
    // 전에 수행되는 Win32 계층(HWND 생성, KSWin32HandleRegistry 등록)을
    // 독립적으로 검증한다.

    @Suite("Win32Window — direct Win32 layer integration", .serialized)
    @MainActor
    struct Win32WindowIntegrationTests {

        private func makeConfig() -> KSWindowConfig {
            KSWindowConfig(
                label: "ks-test-w32-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS Win32 Test",
                width: 320,
                height: 240,
                visible: false
            )
        }

        /// Win32 창이 생성되면 `KSWin32HandleRegistry`에 레이블로 등록돼야 한다.
        @Test("Win32Window init registers label in KSWin32HandleRegistry")
        func initRegistersInHandleRegistry() throws {
            let config = makeConfig()
            let window = try Win32Window(config: config)
            defer { window.close() }

            let handle = KSWin32HandleRegistry.shared.handle(for: config.label)
            #expect(handle != nil)
            #expect(handle?.label == config.label)
        }

        /// Win32 창이 생성되면 `Win32App.shared.allWindows()`에 포함돼야 한다.
        @Test("Win32Window init registers in Win32App.shared")
        func initRegistersInWin32App() throws {
            let config = makeConfig()
            let window = try Win32Window(config: config)
            defer { window.close() }

            #expect(Win32App.shared.allWindows().contains { $0 === window })
        }

        /// `close()` (`DestroyWindow`) 후 `KSWin32HandleRegistry`에서 제거돼야 한다.
        @Test("Win32Window close() unregisters from KSWin32HandleRegistry")
        func closeUnregistersFromHandleRegistry() throws {
            let config = makeConfig()
            let window = try Win32Window(config: config)
            window.close()

            let handle = KSWin32HandleRegistry.shared.handle(for: config.label)
            #expect(handle == nil)
        }

        /// `close()` 후 `Win32App.shared.allWindows()`에서 제거돼야 한다.
        @Test("Win32Window close() removes from Win32App.shared")
        func closeRemovesFromWin32App() throws {
            let config = makeConfig()
            let window = try Win32Window(config: config)
            window.close()

            #expect(!Win32App.shared.allWindows().contains { $0 === window })
        }

        /// `transparent: false` 인 경우 WS_EX_LAYERED 플래그가 설정되지 않는다.
        @Test("transparent=false 윈도우는 WS_EX_LAYERED 가 꺼진다")
        func transparentFalseHasNoLayeredFlag() throws {
            let config = KSWindowConfig(
                label: "ks-test-w32-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS Win32 Test",
                width: 320,
                height: 240,
                transparent: false,
                visible: false)
            let window = try Win32Window(config: config)
            defer { window.close() }
            #expect(window.transparent == false)

            let hwnd = try #require(window.hwnd)
            let exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
            #expect((exStyle & LONG_PTR(WS_EX_LAYERED)) == 0)
        }

        /// `transparent: true` 인 경우 WS_EX_LAYERED 가 켜져 있고
        /// 알파가 설정되어 있다 (255 = 완전 불투명, WebView 알파에 위임).
        @Test("transparent=true 윈도우는 WS_EX_LAYERED 플래그를 가진다")
        func transparentTrueHasLayeredFlag() throws {
            let config = KSWindowConfig(
                label: "ks-test-w32-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS Win32 Test (transparent)",
                width: 320,
                height: 240,
                transparent: true,
                visible: false)
            let window = try Win32Window(config: config)
            defer { window.close() }
            #expect(window.transparent == true)

            let hwnd = try #require(window.hwnd)
            let exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
            #expect((exStyle & LONG_PTR(WS_EX_LAYERED)) != 0)
        }
    }

    // MARK: - KSWindowsWindowBackend.create() 계약 테스트
    //
    // `create()` 는 Win32 창 생성 + WebView2 초기화를 순서대로 수행한다.
    // 테스트 바이너리 컨텍스트에서 WebView2 컨트롤러가 null을 반환하는 경우
    // (숨겨진 HWND 등)에는 `webviewInitFailed` 에러가 발생하며,
    // 이때 cleanup 경로(window.close())가 실행되어야 한다.
    //
    // 이 스위트는 성공/실패 양쪽 경로를 모두 검증한다:
    //   - 성공 → 핸들 반환, find/all 검색 가능
    //   - webviewInitFailed → Win32 창이 정리(find = nil)
    //   - windowCreationFailed → Win32 계층 자체 오류: 진짜 실패

    @Suite("KSWindowsWindowBackend — create() contract", .serialized)
    struct KSWindowsWindowBackendCreateTests {

        private static func makeConfig(visible: Bool = false) -> KSWindowConfig {
            KSWindowConfig(
                label: "ks-test-be-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS Backend Test",
                width: 400,
                height: 300,
                visible: visible
            )
        }

        /// `create()` 가 `windowCreationFailed` 를 던지면 Win32 계층 오류이므로
        /// 진짜 실패다. `webviewInitFailed` 는 환경 제약(테스트 컨텍스트에서
        /// WebView2 컨트롤러 반환 불가)이므로 cleanup 이 완료됐는지만 검증한다.
        @Test("create() — Win32 layer succeeds; WebView2 failure triggers cleanup")
        func createCleanupOnWebViewFailure() async {
            let backend = KSWindowsWindowBackend()
            let config = Self.makeConfig()

            do {
                let handle = try await backend.create(config)
                // WebView2 초기화까지 성공한 경우 — 핸들 검증 후 정리.
                #expect(handle.label == config.label)
                #expect(handle.rawValue != 0)
                try? await backend.close(handle)
            } catch let e
                where e.code == .webviewInitFailed
                || e.code == .platformInitFailed
            {
                // WebView2 컨트롤러가 테스트 컨텍스트에서 null을 반환하는
                // 알려진 환경 제약. Win32 창은 이미 cleanup됐어야 한다.
                let found = await backend.find(label: config.label)
                #expect(
                    found == nil,
                    "create() must clean up the Win32 window on WebView2 failure")
            } catch let e {
                // windowCreationFailed 등 Win32 계층 오류 — 진짜 실패.
                Issue.record("create() failed at Win32 layer (unexpected): \(e)")
            }
        }

        /// `create()` 성공 시 `find(label:)` 이 해당 핸들을 반환해야 한다.
        @Test("create() — handle is findable after successful init")
        func createRegistersInFindOnSuccess() async {
            let backend = KSWindowsWindowBackend()
            let config = Self.makeConfig()

            do {
                let handle = try await backend.create(config)
                let found = await backend.find(label: config.label)
                try? await backend.close(handle)
                #expect(found?.label == config.label)
            } catch let e
                where e.code == .webviewInitFailed
                || e.code == .platformInitFailed
            {
                // 환경 제약 — 이 어설션은 WebView2 가 성공했을 때만 유효.
            } catch let e {
                Issue.record("create() failed at Win32 layer: \(e)")
            }
        }

        /// `create()` 성공 시 `all()` 에 해당 창이 포함돼야 한다.
        @Test("create() — window appears in all() after successful init")
        func createAppearsInAllOnSuccess() async {
            let backend = KSWindowsWindowBackend()
            let config = Self.makeConfig()

            do {
                let handle = try await backend.create(config)
                let all = await backend.all()
                try? await backend.close(handle)
                #expect(all.contains { $0.label == config.label })
            } catch let e
                where e.code == .webviewInitFailed
                || e.code == .platformInitFailed
            {
                // 환경 제약
            } catch let e {
                Issue.record("create() failed at Win32 layer: \(e)")
            }
        }

        /// `create()` 성공 후 `close()` 하면 `find(label:)` 이 `nil`을 반환해야 한다.
        @Test("close() — unregisters handle after successful create()")
        func closeUnregistersAfterSuccessfulCreate() async {
            let backend = KSWindowsWindowBackend()
            let config = Self.makeConfig()

            do {
                let handle = try await backend.create(config)
                try await backend.close(handle)
                let found = await backend.find(label: config.label)
                #expect(found == nil)
            } catch let e
                where e.code == .webviewInitFailed
                || e.code == .platformInitFailed
            {
                // create() 가 실패했으므로 close() 계약은 검증 불가.
                // Win32 창 cleanup 은 위 테스트에서 이미 검증됨.
            } catch let e {
                Issue.record("Unexpected error: \(e)")
            }
        }
    }

    // MARK: - KSWindowsWindowBackend.webView(for:) 계약 테스트
    //
    // `webView(for:)` 는 `create()` 로 만들어진 창에서 `WebView2Host` 를 반환한다.
    // WebView2 초기화가 성공한 경우에만 의미 있으며, 이 스위트는 그 경로를
    // 검증한다.

    @Suite("KSWindowsWindowBackend — webView(for:) contract", .serialized)
    struct KSWindowsWindowBackendWebViewTests {

        private static func makeConfig() -> KSWindowConfig {
            KSWindowConfig(
                label: "ks-test-wv-\(UUID().uuidString.prefix(8).lowercased())",
                title: "KS WebView Test",
                width: 400,
                height: 300,
                visible: false
            )
        }

        /// `create()` 성공 후 `webView(for:)` 는 `KSWebViewBackend` 를 반환해야 한다.
        @Test("webView(for:) returns KSWebViewBackend after successful create()")
        func webViewReturnsBackendAfterCreate() async {
            let backend = KSWindowsWindowBackend()
            let config = Self.makeConfig()

            do {
                let handle = try await backend.create(config)
                let webview = try await backend.webView(for: handle)
                try? await backend.close(handle)
                // 반환된 existential은 절대 nil이 아니다.
                _ = webview
            } catch let e
                where e.code == .webviewInitFailed
                || e.code == .platformInitFailed
            {
                // WebView2 환경 제약 — 이 경로는 테스트 컨텍스트에서 스킵.
            } catch let e {
                Issue.record("webView(for:) contract failed: \(e)")
            }
        }

        /// `close()` 후 `webView(for:)` 는 `windowCreationFailed` 를 반환해야 한다.
        @Test("webView(for:) throws windowCreationFailed after close()")
        func webViewThrowsAfterClose() async {
            let backend = KSWindowsWindowBackend()
            let config = Self.makeConfig()

            do {
                let handle = try await backend.create(config)
                try await backend.close(handle)

                do {
                    _ = try await backend.webView(for: handle)
                    Issue.record("Expected windowCreationFailed after close")
                } catch let e {
                    #expect(
                        e.code == .windowCreationFailed,
                        "Got \(e.code), expected windowCreationFailed")
                }
            } catch let e
                where e.code == .webviewInitFailed
                || e.code == .platformInitFailed
            {
                // WebView2 환경 제약
            } catch let e {
                Issue.record("Unexpected error: \(e)")
            }
        }
    }
#endif
