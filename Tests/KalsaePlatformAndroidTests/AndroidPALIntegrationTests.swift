#if os(Android)
    import Testing
    import Foundation
    @testable import KalsaePlatformAndroid
    import KalsaeCore

    /// PAL 통합 시나리오 — `KSAndroidMenuBackend` 의 핸들러 주입 / JNI 기본
    /// 핸들러 / `KSAndroidCommandRouter` 라우팅이 한 흐름으로 잘 맞물리는지
    /// 확인한다. 다이얼로그 백엔드의 단위 테스트(`AndroidUnsupportedBackends
    /// Tests`)와 중복되지 않도록 컨텍스트 메뉴 셀렉션 경로에 집중한다.
    @Suite("KSAndroidPlatform — PAL 통합 (메뉴 + 라우터)")
    struct AndroidPALIntegrationTests {

        // MARK: - 1. 주입된 핸들러를 통한 셀렉션 라우팅

        @Test("showContextMenu: 주입 핸들러가 선택한 항목의 command 를 라우터로 디스패치한다")
        @MainActor
        func showContextMenuDispatchesCommandViaRouter() async {
            let backend = KSAndroidMenuBackend()
            backend.onShowContextMenu = { items, _, _ in
                // 라벨 "Open" 항목을 선택한 것으로 시뮬레이션.
                return items.firstIndex { $0.label == "Open" }
            }

            // 라우터 초기화 + 구독.
            KSAndroidCommandRouter.shared.clear()
            var captured: (command: String, itemID: String?)?
            KSAndroidCommandRouter.shared.subscribe { cmd, id in
                captured = (cmd, id)
            }

            let items: [KSMenuItem] = [
                KSMenuItem.action(id: "open", label: "Open", command: "file.open"),
                KSMenuItem.action(id: "save", label: "Save", command: "file.save"),
            ]
            do {
                try await backend.showContextMenu(
                    items, at: KSPoint(x: 10, y: 20), in: nil)
            } catch {
                Issue.record("showContextMenu should not throw: \(error)")
            }

            #expect(captured?.command == "file.open")
            #expect(captured?.itemID == "open")

            KSAndroidCommandRouter.shared.clear()
        }

        // MARK: - 2. 취소(nil 반환)는 디스패치하지 않는다

        @Test("showContextMenu: 핸들러가 nil 을 반환하면 라우터로 아무 것도 디스패치되지 않는다")
        @MainActor
        func showContextMenuCancelDoesNotDispatch() async {
            let backend = KSAndroidMenuBackend()
            backend.onShowContextMenu = { _, _, _ in nil }

            KSAndroidCommandRouter.shared.clear()
            var calls = 0
            KSAndroidCommandRouter.shared.subscribe { _, _ in calls += 1 }

            let items: [KSMenuItem] = [
                KSMenuItem.action(id: "x", label: "X", command: "x")
            ]
            do {
                try await backend.showContextMenu(
                    items, at: .init(x: 0, y: 0), in: nil)
            } catch {
                Issue.record("should not throw: \(error)")
            }
            #expect(calls == 0)

            KSAndroidCommandRouter.shared.clear()
        }

        // MARK: - 3. 핸들러 미주입 — 조용히 종료(no-throw)

        @Test("showContextMenu: 핸들러 미주입 시 조용히 종료한다(throw 없음 — default-deny)")
        @MainActor
        func showContextMenuNoHandlerSilent() async {
            let backend = KSAndroidMenuBackend()
            do {
                try await backend.showContextMenu(
                    [], at: .init(x: 0, y: 0), in: nil)
            } catch {
                Issue.record(
                    "Without handler, showContextMenu must be silent no-op, "
                        + "not throw: \(error)")
            }
        }

        // MARK: - 4. installAppMenu / installWindowMenu 는 영구 no-op

        @Test("installAppMenu / installWindowMenu 는 Android 단일 Activity 모델에서 의도적 no-op")
        func appAndWindowMenusAreNoOp() async {
            let backend = KSAndroidMenuBackend()
            do {
                try await backend.installAppMenu([
                    KSMenuItem.action(id: "x", label: "X", command: "x")
                ])
                try await backend.installWindowMenu(
                    KSWindowHandle(label: "main", rawValue: 1),
                    items: [KSMenuItem.action(id: "y", label: "Y", command: "y")])
            } catch {
                Issue.record("App/Window menus should be silent no-op: \(error)")
            }
        }

        // MARK: - 5. installJNIDefaults 비파괴

        @Test("installJNIDefaults: 이미 명시 핸들러가 주입되어 있으면 덮어쓰지 않는다(D2)")
        @MainActor
        func installJNIDefaultsIsNonDestructive() async {
            let backend = KSAndroidMenuBackend()
            // 명시 핸들러 — 항상 0 반환.
            backend.onShowContextMenu = { _, _, _ in 0 }

            // 비파괴 — 명시 핸들러가 유지되어야 한다.
            backend.installJNIDefaults()

            KSAndroidCommandRouter.shared.clear()
            var captured: String?
            KSAndroidCommandRouter.shared.subscribe { cmd, _ in captured = cmd }

            let items: [KSMenuItem] = [
                KSMenuItem.action(id: "k", label: "K", command: "custom.k")
            ]
            do {
                try await backend.showContextMenu(
                    items, at: .init(x: 0, y: 0), in: nil)
            } catch {
                Issue.record("should not throw: \(error)")
            }
            // 명시 핸들러가 보존되었으므로 항목 0 의 command "custom.k" 가
            // 라우팅된다.
            #expect(captured == "custom.k")

            KSAndroidCommandRouter.shared.clear()
        }

        // MARK: - 6. installJNIDefaults — 미주입 상태에서는 JNI 훅이 없으면 nil

        @Test("installJNIDefaults: 명시 핸들러 부재 + JNI 훅 미등록 시 결과는 nil(취소 동등)")
        @MainActor
        func installJNIDefaultsWithoutHookYieldsCancel() async {
            let backend = KSAndroidMenuBackend()
            backend.installJNIDefaults()

            KSAndroidCommandRouter.shared.clear()
            var calls = 0
            KSAndroidCommandRouter.shared.subscribe { _, _ in calls += 1 }

            let items: [KSMenuItem] = [
                KSMenuItem.action(id: "z", label: "Z", command: "z")
            ]
            // JNI 훅이 등록되어 있지 않은 단위테스트 환경에서는 selectedIndex
            // 가 도착하지 않으므로 기본 핸들러는 즉시 nil(취소)로 종료한다.
            do {
                try await backend.showContextMenu(
                    items, at: .init(x: 0, y: 0), in: nil)
            } catch {
                Issue.record("should not throw: \(error)")
            }
            #expect(calls == 0)
            KSAndroidCommandRouter.shared.clear()
        }
    }
#endif
