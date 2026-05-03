#if os(Windows)
    import Testing
    import Foundation
    import WinSDK
    @testable import KalsaePlatformWindows
    import KalsaeCore

    // MARK: - 디스플레이 열거 계약 테스트
    //
    // `KSWindowsWindowBackend.listDisplays()` 는 현재 연결된 모든 모니터 목록을
    // Win32 `EnumDisplayMonitors` + `GetMonitorInfoW` + `GetDpiForMonitor` 로 수집한다.
    // 이 스위트는 "최소 1개 반환", "isPrimary 정확히 1개", "scaleFactor 범위",
    // "workArea ⊆ bounds" 등 플랫폼 독립 계약을 검증한다.

    @Suite("KSWindowsDisplays — listDisplays contract")
    struct KSWindowsDisplaysTests {

        let backend = KSWindowsWindowBackend()

        /// 연결된 모니터가 최소 1개 있어야 한다.
        @Test("listDisplays는 최소 1개의 디스플레이를 반환한다")
        func listDisplaysReturnsAtLeastOne() async throws {
            let displays = try await backend.listDisplays()
            #expect(!displays.isEmpty, "연결된 모니터가 없으면 이 테스트를 실행할 수 없다")
        }

        /// isPrimary가 정확히 1개 있어야 한다.
        @Test("listDisplays는 isPrimary가 정확히 1개인 디스플레이를 반환한다")
        func exactlyOnePrimary() async throws {
            let displays = try await backend.listDisplays()
            let primaries = displays.filter { $0.isPrimary }
            #expect(primaries.count == 1, "isPrimary 디스플레이가 정확히 1개여야 한다 (현재: \(primaries.count))")
        }

        /// scaleFactor는 0.5 ≤ x ≤ 4.0 범위 안에 있어야 한다.
        @Test("모든 디스플레이의 scaleFactor가 0.5 ≤ x ≤ 4.0 범위다")
        func scaleFactorInRange() async throws {
            let displays = try await backend.listDisplays()
            for d in displays {
                #expect(
                    d.scaleFactor >= 0.5 && d.scaleFactor <= 4.0,
                    "디스플레이 '\(d.name)'의 scaleFactor \(d.scaleFactor)가 범위 밖이다")
            }
        }

        /// workArea는 bounds 안에 완전히 포함돼야 한다.
        @Test("모든 디스플레이의 workArea가 bounds 안에 포함된다")
        func workAreaInsideBounds() async throws {
            let displays = try await backend.listDisplays()
            for d in displays {
                #expect(
                    d.bounds.contains(d.workArea),
                    "디스플레이 '\(d.name)': workArea \(d.workArea)가 bounds \(d.bounds) 밖이다")
            }
        }

        /// bounds의 width/height가 양수여야 한다.
        @Test("모든 디스플레이의 bounds width/height가 양수다")
        func boundsPositiveDimensions() async throws {
            let displays = try await backend.listDisplays()
            for d in displays {
                #expect(d.bounds.width > 0, "'\(d.name)' bounds.width ≤ 0")
                #expect(d.bounds.height > 0, "'\(d.name)' bounds.height ≤ 0")
            }
        }

        /// id가 빈 문자열이 아니어야 한다.
        @Test("모든 디스플레이의 id가 비어있지 않다")
        func idNotEmpty() async throws {
            let displays = try await backend.listDisplays()
            for d in displays {
                #expect(!d.id.isEmpty, "디스플레이 id가 빈 문자열이다")
            }
        }

        /// Codable round-trip — listDisplays 결과가 JSON 직렬화/역직렬화에서 보존돼야 한다.
        @Test("KSDisplayInfo Codable round-trip")
        func displayInfoRoundTrip() throws {
            let original = KSDisplayInfo(
                id: "000000000001234A",
                name: "\\\\.\\DISPLAY1",
                bounds: KSRect(x: 0, y: 0, width: 2560, height: 1440),
                workArea: KSRect(x: 0, y: 0, width: 2560, height: 1400),
                scaleFactor: 1.25,
                refreshRate: 144,
                isPrimary: true)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(KSDisplayInfo.self, from: data)
            #expect(decoded == original)
        }
    }

    // MARK: - 태스크바 진행률 계약 테스트
    //
    // ITaskbarList3는 GUI 없이 단위 테스트하기 어렵다.
    // 알 수 없는 핸들로 호출 시 에러가 발생하는지만 검증한다.

    @Suite("KSWindowsTaskbar — setTaskbarProgress contract")
    struct KSWindowsTaskbarTests {

        let backend = KSWindowsWindowBackend()

        /// 존재하지 않는 핸들로 setTaskbarProgress를 호출하면
        /// `windowCreationFailed` 에러가 나와야 한다.
        @Test("존재하지 않는 핸들로 setTaskbarProgress는 windowCreationFailed를 던진다")
        func setProgressUnknownHandleThrows() async {
            let handle = KSWindowHandle(label: "ks-test-taskbar-ghost", rawValue: 0)
            do {
                try await backend.setTaskbarProgress(handle, progress: .normal(0.5))
                Issue.record("Expected windowCreationFailed to be thrown")
            } catch let e {
                #expect(e.code == .windowCreationFailed)
            }
        }

        /// 존재하지 않는 핸들로 setOverlayIcon을 호출하면
        /// `windowCreationFailed` 에러가 나와야 한다.
        @Test("존재하지 않는 핸들로 setOverlayIcon은 windowCreationFailed를 던진다")
        func setOverlayIconUnknownHandleThrows() async {
            let handle = KSWindowHandle(label: "ks-test-icon-ghost", rawValue: 0)
            do {
                try await backend.setOverlayIcon(handle, iconPath: nil, description: nil)
                Issue.record("Expected windowCreationFailed to be thrown")
            } catch let e {
                #expect(e.code == .windowCreationFailed)
            }
        }
    }
#endif
