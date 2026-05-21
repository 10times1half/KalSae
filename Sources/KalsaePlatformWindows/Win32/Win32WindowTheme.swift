#if os(Windows)
    internal import WinSDK
    internal import KalsaeCore

    extension Win32Window {

        /// DWM(데스크톱 창 관리자)의 immersive dark-mode 속성을 통해
        /// 윈도우 테마를 적용한다. Win10 19H2+에서는 속성 인덱스 20,
        /// 이전 빌드에서는 19를 사용하며, 둘 다 실패하면 조용히 무시된다.
        ///
        /// - Parameter theme: `.dark`, `.light`, `.system`(OS 설정 따름)
        func setTheme(_ theme: KSWindowTheme) {
            let log = KSLog.logger("platform.windows.theme")
            log.debug("setTheme: enter theme=\(theme)")
            currentTheme = theme
            guard let hwnd else {
                log.warning("setTheme: hwnd is nil, abort")
                return
            }
            let dark: Bool
            switch theme {
            case .dark: dark = true
            case .light: dark = false
            case .system:
                // HKCU\...\Themes\Personalize에서 AppsUseLightTheme 읽음.
                dark = Self.systemPrefersDark()
            }
            log.debug("setTheme: about to call _applyImmersiveDarkMode dark=\(dark)")
            // DWM 호출은 `withUnsafePointer` (stdlib 제네릭 클로저)를 거치므로
            // `@MainActor` 상속 상태에서 직접 호출하면 Win32 UI 스레드에서
            // `dispatch_assert_queue` 트랩이 발생한다. nonisolated 헬퍼로 위임.
            // 자세한 패턴: /memories/repo/windows-mainactor-closure-trap.md
            Self._applyImmersiveDarkMode(hwnd: hwnd, dark: dark)
            log.debug("setTheme: exit")
        }

        /// DWM immersive dark-mode 속성을 실제로 적용한다.
        /// Win10 19H2+에서는 속성 인덱스 20, 이전 빌드에서는 19를 사용하며,
        /// 둘 다 실패하면 조용히 무시된다.
        ///
        /// `nonisolated internal`: 액터 격리 회귀 방지를 위해 (a) 호출자 액터
        /// 무관, (b) `@testable` 에서 시그니처 단언이 가능해야 한다. 변경 시
        /// `Win32WindowThemeTests` 의 컴파일타임 캡처 단언이 깨진다.
        nonisolated
            internal static func _applyImmersiveDarkMode(hwnd: HWND, dark: Bool)
        {
            var enable: Int32 = dark ? 1 : 0
            let immersiveDarkModeAttribute: DWORD = 20
            let immersiveDarkModeAttributeLegacy: DWORD = 19
            let size = DWORD(MemoryLayout<Int32>.size)
            var hr = withUnsafePointer(to: &enable) { ptr -> Int32 in
                DwmSetWindowAttribute(hwnd, immersiveDarkModeAttribute, ptr, size)
            }
            if hr < 0 {
                hr = withUnsafePointer(to: &enable) { ptr -> Int32 in
                    DwmSetWindowAttribute(hwnd, immersiveDarkModeAttributeLegacy, ptr, size)
                }
            }
            _ = hr
        }

        /// Windows 레지스트리 `HKCU\...\Themes\Personalize\AppsUseLightTheme`를
        /// 읽어 현재 시스템 다크모드 선호도를 알아낸다.
        /// 레지스트리 접근에 실패하면 기본값 `false`(라이트)를 반환한다.
        /// `nonisolated`: 내부 `withUTF16Pointer` (stdlib 제네릭 클로저)가
        /// `@MainActor` 컨텍스트에서 호출되면 Win32 UI 스레드에서
        /// `dispatch_assert_queue` 트랩이 발생하므로 격리 해제.
        nonisolated
            fileprivate static func systemPrefersDark() -> Bool
        {
            let subkey = #"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"#
            let valueName = "AppsUseLightTheme"
            var hkey: HKEY?
            // KEY_READ 매크로는 Swift WinSDK 오버레이에 import되지 않는다.
            // 문서화된 수치값을 직접 쓴다 (STANDARD_RIGHTS_READ |
            // KEY_QUERY_VALUE | KEY_ENUMERATE_SUB_KEYS | KEY_NOTIFY) &
            // ~SYNCHRONIZE = 0x20019.
            let keyReadNumeric: DWORD = 0x20019
            let openHR = subkey.withUTF16Pointer { sk -> Int32 in
                RegOpenKeyExW(HKEY_CURRENT_USER, sk, 0, keyReadNumeric, &hkey)
            }
            guard openHR == 0, let hkey else { return false }
            defer { _ = RegCloseKey(hkey) }
            var data: DWORD = 1
            var len = DWORD(MemoryLayout<DWORD>.size)
            let qHR = valueName.withUTF16Pointer { vn -> Int32 in
                withUnsafeMutablePointer(to: &data) { dataPtr in
                    dataPtr.withMemoryRebound(to: BYTE.self, capacity: Int(len)) { bytes in
                        RegQueryValueExW(hkey, vn, nil, nil, bytes, &len)
                    }
                }
            }
            guard qHR == 0 else { return false }
            return data == 0
        }
    }
#endif
