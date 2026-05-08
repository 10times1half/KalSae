# RFC-004 — macOS PAL Windows 동등성 반영

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-08 |
| 영향 범위 | KalsaePlatformMac PAL 전반 |
| 관련 | AGENTS.md §5 (Platform Notes) |

---

## 1. 동기(Motivation)

Windows PAL은 **풀 커버리지**(윈도우, 다이얼로그, 트레이, 메뉴, 알림, 클립보드,
셸, 가속기, 자동시작, 딥링크, 단일 인스턴스, 디스플레이 열거, 작업 표시줄 진행률,
오버레이 아이콘, 파일 드롭, 투명 윈도우, 윈도우 상태 영속화)를 완전히 구현하고 있다.

macOS PAL은 기본 기능(윈도우/다이얼로그/트레이/메뉴/알림/셸/클립보드/가속기/자동시작/
딥링크/싱글인스턴스)에서 Windows와 동등하지만, 다음 **5가지 영역**이 누락되어 있다:

1. **윈도우 상태 복원 (로드)** — 저장은 되지만 재시작 시 로드/적용이 없음
2. **디스플레이 열거** — `listDisplays()` / `currentDisplay()` 미구현
3. **Dock 진행률 / 오버레이 아이콘** — `setTaskbarProgress()` / `setOverlayIcon()` 미구현
4. **파일 드롭 이벤트 전달** — `installFileDropEmitter()` / `setAllowExternalDrop()` 스텁
5. **투명 윈도우** — 1회 경고 로그만 출력하고 무시

이 RFC는 위 5개 갭을 해소하여 macOS와 Windows 간 기능 동등성을 확보한다.

---

## 2. 확정된 결정사항

| 결정 | 선택 | 근거 |
|------|------|------|
| 구현 범위 | 5개 갭 전부 반영 | Windows와 완전한 동등성 확보 |
| Dock Progress 전략 | 마지막 `setTaskbarProgress()` 호출 윈도우 기준 | macOS Dock은 앱 전역(`NSDockTile`)이라 per-window 불가; 마지막 호출 윈도우의 진행률을 표시하는 것이 가장 직관적 |
| 파일 구조 | Windows PAL과 동일하게 `+Displays.swift`, `+Taskbar.swift`로 분리 | 일관된 코드 구조 유지 |
| 테스트 | 이번 스코프에서 생략 | macOS CI 미설정 상태; 로컬 수동 검증으로 대체 |

---

## 3. 현재 상태 비교

### 3.1 동등 영역 (변경 불필요)

| PAL 영역 | Windows | macOS |
|---|---|---|
| Window (생성/닫기/표시/숨기기/포커스) | ✅ | ✅ |
| Window Geometry (크기/위치/최소최대/센터) | ✅ | ✅ |
| Window State (최소화/최대화/복원/전체화면/항상위) | ✅ | ✅ |
| Window Visual (제목/테마/배경색/줌/인쇄/캡처) | ✅ | ✅ |
| Close Interceptor | ✅ | ✅ |
| Dialogs (openFile/saveFile/selectFolder/message) | ✅ | ✅ |
| Tray (install/tooltip/menu/remove) | ✅ | ✅ |
| Menu (appMenu/windowMenu/contextMenu) | ✅ | ✅ |
| Notifications (permission/post/cancel) | ✅ | ✅ |
| Shell (openExternal/showInFolder/moveToTrash) | ✅ | ✅ |
| Clipboard (text/image read·write + clear + hasFormat) | ✅ | ✅ |
| Accelerators (register/unregister/unregisterAll) | ✅ | ✅ |
| Autostart (enable/disable/isEnabled) | ✅ | ✅ |
| Deep Link (register/unregister/isRegistered/URLs) | ✅ | ✅ |
| Single Instance (acquire) | ✅ | ✅ |
| Virtual Host (`ks://` scheme handler) | ✅ | ✅ |
| Window State Persistence (저장) | ✅ | ✅ |
| Suspend/Resume lifecycle events | ✅ | ✅ |

### 3.2 누락 영역

| PAL 영역 | Windows | macOS | 갭 설명 |
|---|---|---|---|
| Window State 복원 (로드) | ✅ `restoredState` | ❌ 저장만 | `stateStore.load()` 호출 없음, `KSMacDemoHost`에 파라미터 없음 |
| Display Enumeration | ✅ `EnumDisplayMonitors` | ❌ 기본 throw | `listDisplays()` / `currentDisplay()` 미구현 |
| Taskbar/Dock Progress | ✅ `ITaskbarList3` | ❌ 기본 no-op | `setTaskbarProgress()` 미구현 |
| Overlay Icon | ✅ `ITaskbarList3` | ❌ 기본 no-op | `setOverlayIcon()` 미구현 |
| File Drop Emitter | ✅ `RegisterDragDrop` | ❌ 스텁 | `installFileDropEmitter()` 없음, `setAllowExternalDrop()` 스텁 |
| Transparent Window | ✅ `WS_EX_LAYERED` | ❌ 경고만 | `warnTransparentOnce()` 출력 후 무시 |

---

## 4. 상세 구현 계획

모든 Phase는 상호 독립적이며 병렬 진행이 가능하다.

---

### Phase 1: Window State 복원 (P0 — 필수, 난이도 낮음)

#### 1.1 문제 분석

Windows `KSWindowsPlatform.runOnMain()` (line ~77):

```swift
let restoredState = stateStore?.load(label: window.label)   // ← 로드
let host = try KSWindowsDemoHost(
    windowConfig: window,
    registry: commandRegistry,
    restoredState: restoredState)                            // ← 전달
```

macOS `KSMacPlatform.runOnMain()` (line ~82):

```swift
// stateStore?.load() 호출이 없음
let host = try KSMacDemoHost(
    windowConfig: window,
    registry: commandRegistry)                               // ← restoredState 없음
```

Windows `Win32Window.init` (line ~124):

```swift
if let restored = restoredState,
    Self.rectIntersectsAnyMonitor(
        x: restored.x, y: restored.y,
        width: restored.width, height: restored.height) {
    _ = SetWindowPos(hwnd, nil,
        Int32(restored.x), Int32(restored.y),
        Int32(restored.width), Int32(restored.height),
        UINT(SWP_NOZORDER) | UINT(SWP_NOACTIVATE))
}
```

macOS `KSMacWindow.init` (line ~21):

```swift
public init(config: KSWindowConfig) throws(KSError) {
    // restoredState 파라미터 자체가 없음
}
```

#### 1.2 변경 내역

**파일 1: `Sources/KalsaePlatformMac/KSMacPlatform.swift`**

**(a) `runOnMain()` — 상태 로드 추가** (line ~82 부근)

현재:
```swift
let stateStore: KSWindowStateStore? =
    window.persistState
    ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
    : nil

let host = try KSMacDemoHost(
    windowConfig: window,
    registry: commandRegistry)
```

변경:
```swift
let stateStore: KSWindowStateStore? =
    window.persistState
    ? KSWindowStateStore.standard(forIdentifier: config.app.identifier)
    : nil
let restoredState = stateStore?.load(label: window.label)           // 추가

let host = try KSMacDemoHost(
    windowConfig: window,
    registry: commandRegistry,
    restoredState: restoredState)                                    // 변경
```

**(b) `KSMacDemoHost.init` — 파라미터 추가** (line ~316 부근)

현재:
```swift
public init(
    windowConfig: KSWindowConfig,
    registry: KSCommandRegistry
) throws(KSError) {
    KSMacApp.shared.ensureInitialized()
    self.registry = registry
    self.window = try KSMacWindow(config: windowConfig)
    // ...
}
```

변경:
```swift
public init(
    windowConfig: KSWindowConfig,
    registry: KSCommandRegistry,
    restoredState: KSPersistedWindowState? = nil                    // 추가
) throws(KSError) {
    KSMacApp.shared.ensureInitialized()
    self.registry = registry
    self.window = try KSMacWindow(config: windowConfig,
                                  restoredState: restoredState)     // 변경
    // ...
}
```

**파일 2: `Sources/KalsaePlatformMac/AppKit/KSMacWindow.swift`**

**(a) `init` 시그니처 변경 + 복원 로직 추가** (line ~21 부근)

현재:
```swift
public init(config: KSWindowConfig) throws(KSError) {
    // ... NSWindow 생성 ...
    if config.center { window.center() }
    if config.alwaysOnTop { window.level = .floating }

    if config.transparent {
        Self.warnTransparentOnce(log: log)
    }

    self.nsWindow = window
    // ...
}
```

변경:
```swift
public init(
    config: KSWindowConfig,
    restoredState: KSPersistedWindowState? = nil                    // 추가
) throws(KSError) {
    // ... NSWindow 생성 (기존과 동일) ...
    if config.center { window.center() }
    if config.alwaysOnTop { window.level = .floating }

    // --- 투명 윈도우 (Phase 5에서 변경됨) ---
    if config.transparent {
        Self.warnTransparentOnce(log: log)
    }

    self.nsWindow = window
    // ...

    // --- 영속화된 윈도우 상태 복원 (Phase 1) ---
    if let restored = restoredState,
       Self.rectIntersectsAnyScreen(
           x: restored.x, y: restored.y,
           width: restored.width, height: restored.height)
    {
        let screenH = NSScreen.screens
            .map { $0.frame.maxY }
            .max() ?? 900
        let flippedY = screenH - CGFloat(restored.y) - CGFloat(restored.height)
        nsWindow.setFrame(
            NSRect(x: CGFloat(restored.x), y: flippedY,
                   width: CGFloat(restored.width), height: CGFloat(restored.height)),
            display: true, animate: false)
    }
    // maximized/fullscreen 상태는 윈도우 표시 후에 적용해야 효과가
    // 있으므로 setContentView() 직후에 처리한다.
    if let restored = restoredState {
        if restored.fullscreen {
            nsWindow.toggleFullScreen(nil)
        } else if restored.maximized {
            nsWindow.zoom(nil)
        }
    }
}
```

**(b) 화면 존재 여부 검증 헬퍼 추가** (Windows `rectIntersectsAnyMonitor` 대응)

```swift
/// 복원 좌표가 현재 연결된 모니터 중 하나에 겹치는지 확인한다.
/// Windows `Win32Window.rectIntersectsAnyMonitor()` 대응.
private static func rectIntersectsAnyScreen(
    x: Int, y: Int, width: Int, height: Int
) -> Bool {
    let screens = NSScreen.screens
    guard !screens.isEmpty else { return false }
    let maxY = screens.map { $0.frame.maxY }.max() ?? 0
    // Kalsae 좌표 (top-left) → macOS 좌표 (bottom-left) 변환
    let flippedY = maxY - CGFloat(y) - CGFloat(height)
    let rect = NSRect(
        x: CGFloat(x), y: flippedY,
        width: CGFloat(width), height: CGFloat(height))
    return screens.contains { $0.frame.intersects(rect) }
}
```

#### 1.3 좌표 변환 설명

macOS 좌표계는 **왼쪽 아래**가 원점이고, Kalsae/Windows는 **왼쪽 위**가 원점이다.
기존 `KSMacWindow.setPosition(x:y:)` (line ~85)에서 이미 사용하는 변환 패턴을 동일하게 적용한다:

```
macOS_y = maxScreenY - kalsae_y - height
```

저장 시 `capturePersistedState()` (line ~155)에서 `getPosition()`을 호출하면
이미 Kalsae 좌표계(top-left)로 저장되므로, 복원 시에도 같은 역변환만 적용하면 된다.

#### 1.4 엣지 케이스 처리

| 시나리오 | 동작 |
|---|---|
| 모니터 분리 후 복원 좌표가 화면 밖 | `rectIntersectsAnyScreen` → `false` → 기본 위치(config 또는 center) 유지 |
| `restoredState == nil` (첫 실행) | 복원 로직 스킵, 기존 동작과 동일 |
| `fullscreen + maximized` 동시 `true` | `fullscreen` 우선 (Windows 동일) |
| `persistState == false` (config) | `stateStore` 자체가 `nil` → `restoredState == nil` |

---

### Phase 2: Display Enumeration (P1 — 높음, 난이도 중간)

#### 2.1 문제 분석

`KSWindowBackend` 프로토콜 (line ~125, ~128):
```swift
func listDisplays() async throws(KSError) -> [KSDisplayInfo]
func currentDisplay(_ handle: KSWindowHandle) async throws(KSError) -> KSDisplayInfo
```

기본 구현 (line ~218):
```swift
public func listDisplays() async throws(KSError) -> [KSDisplayInfo] {
    try _unsupportedThrow("listDisplays")
}
```

Windows 구현: `KSWindowsWindowBackend+Displays.swift` — `EnumDisplayMonitors` 콜백으로
`KSDisplayInfo` 배열을 반환하며 `MonitorFromWindow`로 현재 모니터를 식별한다.

macOS: `KSMacWindowBackend`에 두 메서드가 없어 기본 `unsupportedPlatform` throw를 상속.

#### 2.2 변경 내역

**신규 파일: `Sources/KalsaePlatformMac/PAL/KSMacWindowBackend+Displays.swift`**

```swift
#if os(macOS)
    internal import AppKit
    public import KalsaeCore
    import Foundation

    // MARK: - KSMacWindowBackend + Display enumeration

    extension KSMacWindowBackend {

        // MARK: listDisplays

        public func listDisplays() async throws(KSError) -> [KSDisplayInfo] {
            await MainActor.run {
                let screens = NSScreen.screens
                guard !screens.isEmpty else { return [] }
                // macOS 좌표계(좌하단 원점) → Kalsae 가상 데스크톱(좌상단 원점)
                // 전체 화면 영역의 최대 Y를 기준으로 뒤집는다.
                let maxY = screens.reduce(0.0) { max($0, $1.frame.maxY) }
                return screens.enumerated().map { idx, screen in
                    displayInfo(from: screen, maxY: maxY, isPrimary: idx == 0)
                }
            }
        }

        // MARK: currentDisplay

        public func currentDisplay(
            _ handle: KSWindowHandle
        ) async throws(KSError) -> KSDisplayInfo {
            let result: Result<KSDisplayInfo, KSError> = await MainActor.run {
                do {
                    let w = try self.window(for: handle)
                    let screen = w.nsWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]
                    let screens = NSScreen.screens
                    let maxY = screens.reduce(0.0) { max($0, $1.frame.maxY) }
                    let isPrimary = (screen == screens.first)
                    return .success(displayInfo(from: screen, maxY: maxY, isPrimary: isPrimary))
                } catch {
                    return .failure(
                        error as? KSError
                            ?? KSError(code: .internal, message: "\(error)"))
                }
            }
            switch result {
            case .success(let v): return v
            case .failure(let e): throw e
            }
        }

        // MARK: - 내부 헬퍼

        /// NSScreen → KSDisplayInfo 변환. Phase 1의 좌표 변환 패턴과 동일.
        @MainActor
        private func displayInfo(
            from screen: NSScreen,
            maxY: CGFloat,
            isPrimary: Bool
        ) -> KSDisplayInfo {
            let f = screen.frame
            let vf = screen.visibleFrame

            // bounds: 전체 화면 영역 (좌표 변환)
            let bounds = KSRect(
                x: Int(f.minX),
                y: Int(maxY - f.maxY),
                width: Int(f.width),
                height: Int(f.height))

            // workArea: Dock/메뉴바를 제외한 영역 (좌표 변환)
            let workArea = KSRect(
                x: Int(vf.minX),
                y: Int(maxY - vf.maxY),
                width: Int(vf.width),
                height: Int(vf.height))

            // CGDirectDisplayID 추출
            let displayID: CGDirectDisplayID =
                screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? CGDirectDisplayID ?? 0

            // 주사율: CGDisplayCopyDisplayMode 사용
            var refreshRate: Int? = nil
            if let mode = CGDisplayCopyDisplayMode(displayID) {
                let hz = Int(mode.refreshRate)
                if hz > 0 { refreshRate = hz }
            }

            // 디스플레이 이름
            let name: String = screen.localizedName

            return KSDisplayInfo(
                id: String(displayID),
                name: name,
                bounds: bounds,
                workArea: workArea,
                scaleFactor: Double(screen.backingScaleFactor),
                refreshRate: refreshRate,
                isPrimary: isPrimary)
        }
    }
#endif
```

#### 2.3 좌표 변환 상세

```
macOS 좌표계:                      Kalsae 좌표계:
  ┌─ maxY ─────────┐                 ┌─ 0 ──────────────┐
  │                 │                 │                   │
  │  screen.frame   │                 │  KSRect.bounds    │
  │  origin.y = 0   │                 │  y = maxY - maxY  │
  └─ 0 ─────────────┘                 └─ maxY ────────────┘
```

`NSScreen.screens[0]`은 항상 주 모니터(macOS 보장).

#### 2.4 `window(for:)` 접근성 문제

`window(for:)` 헬퍼는 `KSMacWindowBackend` 내부에 `private`으로 선언되어 있다
(line ~35). 확장 파일에서 사용하려면 접근 수준을 `internal`로 변경해야 한다.

`KSMacWindowBackend.swift`에서:
```swift
// 현재: private func window(for handle: ...) ...
// 변경: internal func window(for handle: ...) ...
```

Windows에서도 `windowSync(for:)`가 `internal`로 선언되어 `+Displays.swift`, `+Taskbar.swift`에서 사용된다.

#### 2.5 Windows 대비 API 매핑

| Windows API | macOS API | 비고 |
|---|---|---|
| `EnumDisplayMonitors()` | `NSScreen.screens` | 배열 직접 접근 |
| `GetMonitorInfoW()` → `rcMonitor` | `NSScreen.frame` | |
| `GetMonitorInfoW()` → `rcWork` | `NSScreen.visibleFrame` | Dock/메뉴바 제외 |
| `GetDpiForMonitor()` → DPI/96 | `NSScreen.backingScaleFactor` | Retina = 2.0 |
| `EnumDisplaySettingsW()` → Hz | `CGDisplayCopyDisplayMode()` → `refreshRate` | |
| `MONITORINFOF_PRIMARY` | `screens[0]` | macOS는 첫 번째가 주 |
| `HMONITOR` hex | `CGDirectDisplayID` decimal | |
| `DISPLAY_DEVICE.DeviceName` | `NSScreen.localizedName` | macOS 10.15+ |
| `MonitorFromWindow()` | `NSWindow.screen` | |

---

### Phase 3: Dock Progress / Overlay Icon (P2 — 보통, 난이도 중간)

#### 3.1 문제 분석

`KSWindowState` 프로토콜 (line ~135, ~141):
```swift
func setTaskbarProgress(_ handle: KSWindowHandle, progress: KSTaskbarProgress) async throws(KSError)
func setOverlayIcon(_ handle: KSWindowHandle, iconPath: String?, description: String?) async throws(KSError)
```

기본 구현 (line ~227, ~232): no-op (에러 없이 반환).

Windows: `KSWV2_SetTaskbarProgress(hwnd, state, value)` → C++ shim으로 `ITaskbarList3` COM 호출.
각 HWND(`KSWindowHandle`)마다 독립적으로 작업 표시줄 버튼에 진행률 표시 가능.

macOS: `NSDockTile`은 앱 전역(하나의 Dock 아이콘). per-window 분리 불가.
→ **결정**: 마지막으로 `setTaskbarProgress()`를 호출한 윈도우의 진행률을 표시.

#### 3.2 변경 내역

**신규 파일: `Sources/KalsaePlatformMac/PAL/KSMacWindowBackend+Taskbar.swift`**

```swift
#if os(macOS)
    internal import AppKit
    public import KalsaeCore

    // MARK: - KSMacWindowBackend + Dock/Taskbar integration

    extension KSMacWindowBackend {

        // MARK: setTaskbarProgress

        public func setTaskbarProgress(
            _ handle: KSWindowHandle,
            progress: KSTaskbarProgress
        ) async throws(KSError) {
            // handle의 유효성만 검증 — Dock은 앱 전역이므로 핸들 자체를 사용하지 않는다.
            _ = try await queryMain(handle) { _ in () }
            await MainActor.run {
                let tile = NSApplication.shared.dockTile
                switch progress {
                case .none:
                    tile.contentView = nil
                    tile.badgeLabel = nil
                case .indeterminate:
                    let view = KSDockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
                    view.setIndeterminate()
                    tile.contentView = view
                case .normal(let v):
                    let view = KSDockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
                    view.setProgress(v, color: .controlAccentColor)
                    tile.contentView = view
                case .error(let v):
                    let view = KSDockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
                    view.setProgress(v, color: .systemRed)
                    tile.contentView = view
                case .paused(let v):
                    let view = KSDockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
                    view.setProgress(v, color: .systemYellow)
                    tile.contentView = view
                }
                tile.display()
            }
        }

        // MARK: setOverlayIcon

        public func setOverlayIcon(
            _ handle: KSWindowHandle,
            iconPath: String?,
            description: String?
        ) async throws(KSError) {
            _ = try await queryMain(handle) { _ in () }
            await MainActor.run {
                let tile = NSApplication.shared.dockTile
                if let path = iconPath,
                   let image = NSImage(contentsOfFile: path) {
                    let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
                    view.image = NSApp.applicationIconImage  // 기본 아이콘 선 그린 뒤
                    let overlay = NSImageView(
                        frame: NSRect(x: 80, y: 0, width: 48, height: 48))
                    overlay.image = image
                    view.addSubview(overlay)
                    tile.contentView = view
                    tile.badgeLabel = description
                } else {
                    tile.contentView = nil
                    tile.badgeLabel = nil
                }
                tile.display()
            }
        }
    }

    // MARK: - DockTile 진행률 커스텀 뷰

    /// 128×128 DockTile 영역에 원형 또는 바 형태의 진행률을 그리는 뷰.
    /// `setIndeterminate()` → spinning, `setProgress(_:color:)` → 원형 진행률.
    @MainActor
    private final class KSDockProgressView: NSView {
        private let indicator = NSProgressIndicator()

        override init(frame: NSRect) {
            super.init(frame: frame)
            // 앱 아이콘을 배경으로 유지
            let iconView = NSImageView(frame: bounds)
            iconView.image = NSApp.applicationIconImage
            addSubview(iconView)
            // 하단 바 형태 진행률
            let barFrame = NSRect(x: 8, y: 8, width: bounds.width - 16, height: 12)
            indicator.frame = barFrame
            indicator.style = .bar
            indicator.minValue = 0
            indicator.maxValue = 100
            addSubview(indicator)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func setIndeterminate() {
            indicator.isIndeterminate = true
            indicator.startAnimation(nil)
        }

        func setProgress(_ value: Double, color: NSColor) {
            indicator.isIndeterminate = false
            indicator.doubleValue = (value * 100).clamped(to: 0...100)
            indicator.wantsLayer = true
            indicator.layer?.backgroundColor = color.withAlphaComponent(0.8).cgColor
        }
    }

    private extension Double {
        func clamped(to range: ClosedRange<Double>) -> Double {
            Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
        }
    }
#endif
```

#### 3.3 `queryMain` 접근성

Phase 2와 동일하게 `queryMain`도 `private` → `internal`로 변경이 필요하다.

`KSMacWindowBackend.swift`에서:
```swift
// 현재: private func queryMain<T: Sendable>(...) ...
// 변경: internal func queryMain<T: Sendable>(...) ...
```

#### 3.4 Windows 대비 API 매핑

| Windows API | macOS API | 비고 |
|---|---|---|
| `ITaskbarList3.SetProgressState` | `NSDockTile.contentView` 교체 | 앱 전역 1개 |
| `ITaskbarList3.SetProgressValue` | `NSProgressIndicator.doubleValue` | |
| `TBPF_NOPROGRESS` (0) | `contentView = nil` | |
| `TBPF_INDETERMINATE` (1) | `isIndeterminate = true` | spinning |
| `TBPF_NORMAL` (2) | bar + `controlAccentColor` | |
| `TBPF_ERROR` (3) | bar + `systemRed` | |
| `TBPF_PAUSED` (4) | bar + `systemYellow` | |
| `ITaskbarList3.SetOverlayIcon` | `NSDockTile.contentView` + `NSImageView` overlay | 128×128 뷰 |

#### 3.5 Dock 표시 제약

- Dock 아이콘은 **시스템이 그린다**. `tile.display()`를 호출해야 갱신이 반영된다.
- `NSProgressIndicator`는 Dock 크기(보통 48~128px)에 맞게 렌더링된다.
  바 형태(`.bar`)가 가장 가독성이 좋다.
- `setTaskbarProgress`와 `setOverlayIcon`이 모두 `contentView`를 사용하므로,
  동시 사용 시 마지막 호출이 우선한다 (Windows도 유사 — overlay는 프로그레스 위에 겹침).

---

### Phase 4: File Drop Emitter (P2 — 보통, 난이도 중간)

#### 4.1 문제 분석

Windows 흐름:
1. `KSWindowsDemoHost.setAllowExternalDrop(false)` → `webview.setAllowExternalDrop(false)` → WebView2 내장 드랍 비활성화
2. `KSWindowsDemoHost.installFileDropEmitter()` → `webview.installFileDropHandler(callback)` → C++ shim `KSWV2_RegisterDropTarget()` → Win32 `RegisterDragDrop()` + `IDropTarget` COM
3. 콜백에서 `bridge.emit("__ks.file.drop", payload)` → JS 이벤트

macOS 현재:
- `setAllowExternalDrop(_ allow: Bool)` 은 `{ _ = allow }` 스텁 (line ~430)
- `installFileDropEmitter()` 메서드 자체가 없음
- `WKWebViewHost`에 드래그 관련 코드도 없음

#### 4.2 변경 내역

**파일 1: `Sources/KalsaePlatformMac/WebKit/WKWebViewHost.swift`**

**(a) 드래그 오버레이 뷰 클래스 추가** (파일 하단, `#endif` 직전)

```swift
/// WKWebView 위에 투명하게 얹어 파일 드래그 이벤트를 가로채는 뷰.
/// `NSDraggingDestination` 프로토콜의 메서드를 구현한다.
@MainActor
internal final class KSFileDropOverlay: NSView {
    enum DropEventKind { case enter, leave, drop }

    var handler: ((_ kind: DropEventKind, _ x: Int32, _ y: Int32, _ paths: [String]) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let (paths, pt) = extractInfo(sender)
        let accepted = handler?(.enter, Int32(pt.x), Int32(pt.y), paths) ?? false
        return accepted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        _ = handler?(.leave, 0, 0, [])
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let (paths, pt) = extractInfo(sender)
        return handler?(.drop, Int32(pt.x), Int32(pt.y), paths) ?? false
    }

    private func extractInfo(_ sender: NSDraggingInfo) -> ([String], NSPoint) {
        let pb = sender.draggingPasteboard
        let urls = pb.readObjects(forClasses: [NSURL.self],
                                  options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let paths = urls.map(\.path)
        let pt = convert(sender.draggingLocation, from: nil)
        return (paths, pt)
    }
}
```

**(b) `installFileDropHandler(_:)` 메서드 추가** (`WKWebViewHost` 클래스 내부)

```swift
/// 호스트 측 파일 드롭 타겟을 설치한다. WKWebView 위에 투명 오버레이를
/// 얹어 `NSDraggingDestination`으로 이벤트를 가로챈다.
internal func installFileDropHandler(
    _ handler: @MainActor @escaping (
        KSFileDropOverlay.DropEventKind, Int32, Int32, [String]
    ) -> Bool
) {
    let overlay = KSFileDropOverlay(frame: webView.bounds)
    overlay.autoresizingMask = [.width, .height]
    overlay.handler = handler
    webView.addSubview(overlay)
}
```

**(c) `setAllowExternalDrop(_:)` 메서드 추가** (`WKWebViewHost` 클래스 내부)

```swift
/// WKWebView의 내장 파일 드랍 동작을 비활성화한다.
/// `installFileDropHandler(_:)` 전에 호출해야 한다.
internal func setAllowExternalDrop(_ allow: Bool) {
    if !allow {
        webView.unregisterDraggedTypes()
    }
}
```

**파일 2: `Sources/KalsaePlatformMac/KSMacPlatform.swift`**

**(a) `KSMacDemoHost.installFileDropEmitter()` 추가** (line ~430 부근)

```swift
/// Finder→앱 파일 드롭을 `__ks.file.drop` JS 이벤트로 전달한다.
/// `setAllowExternalDrop(false)` 이후에 호출해야 한다.
/// Windows `KSWindowsDemoHost.installFileDropEmitter()` 대응.
public func installFileDropEmitter() throws(KSError) {
    let bridge = self.bridge
    webview.installFileDropHandler { kind, x, y, paths in
        struct Payload: Encodable {
            let kind: String
            let x: Int32
            let y: Int32
            let paths: [String]
        }
        let kindStr: String
        switch kind {
        case .enter: kindStr = "enter"
        case .leave: kindStr = "leave"
        case .drop:  kindStr = "drop"
        }
        let payload = Payload(kind: kindStr, x: x, y: y, paths: paths)
        try? bridge.emit(event: "__ks.file.drop", payload: payload)
        return !paths.isEmpty || kind == .leave
    }
}
```

**(b) `setAllowExternalDrop(_:)` 스텁 교체** (line ~430)

현재:
```swift
public func setAllowExternalDrop(_ allow: Bool) { _ = allow }
```

변경:
```swift
public func setAllowExternalDrop(_ allow: Bool) {
    webview.setAllowExternalDrop(allow)
}
```

#### 4.3 이벤트 페이로드 스키마 (Windows와 동일)

```json
{
  "kind": "enter" | "leave" | "drop",
  "x": 123,
  "y": 456,
  "paths": ["/Users/foo/Documents/file.txt", "/Users/foo/image.png"]
}
```

JS 소비자는 `__KS_.listen("__ks.file.drop", callback)`으로 수신한다.

#### 4.4 Windows 대비 API 매핑

| Windows API | macOS API | 비고 |
|---|---|---|
| `KSWV2_RegisterDropTarget()` | overlay NSView + `registerForDraggedTypes` | |
| `IDropTarget.DragEnter` | `draggingEntered(_:)` | |
| `IDropTarget.DragLeave` | `draggingExited(_:)` | |
| `IDropTarget.Drop` | `performDragOperation(_:)` | |
| `DROPEFFECT_COPY` | `.copy` | 반환값으로 커서 표시 제어 |
| `webview.setAllowExternalDrop(false)` | `webView.unregisterDraggedTypes()` | WebView 내장 드랍 비활성화 |

#### 4.5 `WKWebView` 위의 오버레이 전략

WKWebView 자체는 `NSDraggingDestination`을 내부적으로 구현할 수 있다.
`unregisterDraggedTypes()`로 WKWebView의 내장 핸들러를 제거한 뒤,
투명 오버레이 뷰를 `addSubview`로 얹어 이벤트를 가로채는 방식이다.

오버레이 뷰는 `autoresizingMask = [.width, .height]`로 리사이즈를 추적하고,
`hitTest`를 오버라이드하지 않으므로 일반 클릭/스크롤은 WKWebView로 전달된다
(드래그 이벤트만 `registerForDraggedTypes`가 활성화한 타입에 대해 가로챈다).

---

### Phase 5: Transparent Window (P3 — 낮음, 난이도 낮음)

#### 5.1 문제 분석

Windows 흐름:
1. `Win32Window.init` — `WS_EX_LAYERED` ex-style 추가 (line ~60)
2. `SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)` (line ~90)
3. `KSWindowsDemoHost.applyVisualOptions()` — `webview.setDefaultBackgroundColor(rgba: 0,0,0,0)` (line ~300)

macOS 현재 (line ~47):
```swift
if config.transparent {
    Self.warnTransparentOnce(log: log)   // 경고만 출력하고 무시
}
```

경고 관련 정적 멤버 (line ~199):
```swift
nonisolated(unsafe) private static var didWarnTransparent = false
nonisolated(unsafe) private static let warnLock = NSLock()

fileprivate static func warnTransparentOnce(log: Logger) {
    warnLock.lock()
    defer { warnLock.unlock() }
    guard !didWarnTransparent else { return }
    didWarnTransparent = true
    log.warning(
        "KSWindowConfig.transparent=true 는 macOS에서 아직 지원되지 않습니다 (Windows 전용, v0.3). 무시됩니다."
    )
}
```

#### 5.2 변경 내역

**파일 1: `Sources/KalsaePlatformMac/AppKit/KSMacWindow.swift`**

**(a) 투명 설정 활성화** (line ~47)

현재:
```swift
if config.transparent {
    Self.warnTransparentOnce(log: log)
}
```

변경:
```swift
if config.transparent {
    window.isOpaque = false
    window.backgroundColor = .clear
}
```

**(b) 정적 경고 멤버 제거** (line ~199)

삭제 대상:
```swift
nonisolated(unsafe) private static var didWarnTransparent = false
nonisolated(unsafe) private static let warnLock = NSLock()

fileprivate static func warnTransparentOnce(log: Logger) {
    warnLock.lock()
    defer { warnLock.unlock() }
    guard !didWarnTransparent else { return }
    didWarnTransparent = true
    log.warning(
        "KSWindowConfig.transparent=true 는 macOS에서 아직 지원되지 않습니다 (Windows 전용, v0.3). 무시됩니다."
    )
}
```

**파일 2: `Sources/KalsaePlatformMac/WebKit/WKWebViewHost.swift`**

**(a) 투명 WebView 배경 메서드 추가** (`WKWebViewHost` 클래스 내부)

```swift
/// 투명 윈도우일 때 WebView 배경을 투명하게 설정한다.
/// NSWindow.isOpaque = false와 함께 사용해야 한다.
internal func setTransparentBackground() {
    webView.setValue(false, forKey: "drawsBackground")
    if #available(macOS 12.0, *) {
        webView.underPageBackgroundColor = .clear
    }
}
```

**파일 1 추가: `KSMacWindow.setContentView` 에서 호출**

현재:
```swift
public func setContentView(_ view: NSView) {
    nsWindow.contentView = view
    if config.visible { nsWindow.makeKeyAndOrderFront(nil) }
}
```

변경:
```swift
public func setContentView(_ view: NSView) {
    nsWindow.contentView = view
    if config.transparent {
        webviewHost?.setTransparentBackground()
    }
    if config.visible { nsWindow.makeKeyAndOrderFront(nil) }
}
```

#### 5.3 Windows 대비 API 매핑

| Windows API | macOS API | 비고 |
|---|---|---|
| `WS_EX_LAYERED` | `NSWindow.isOpaque = false` | DWM 합성 모드 전환 |
| `SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)` | `NSWindow.backgroundColor = .clear` | 윈도우 프레임 버퍼 투명 |
| `webview.setDefaultBackgroundColor(r:0, g:0, b:0, a:0)` | `webView.setValue(false, forKey: "drawsBackground")` + `underPageBackgroundColor = .clear` | WebView 콘텐츠 영역 투명 |

#### 5.4 성능 고려

- `isOpaque = false`를 설정하면 AppKit은 매 프레임을 풀 컴포지팅해야 한다.
  CPU/GPU 사용량이 증가할 수 있으며 배터리 소모에 영향을 준다.
- Windows의 Mica/Acrylic/Tabbed 백드롭 효과는 macOS에서 직접 대응되지 않는다.
  macOS 등가물(`NSVisualEffectView`)은 별도 Phase에서 검토한다.
- 웹 콘텐츠에서 `html, body { background: transparent; }`를 설정하지 않으면
  HTML 배경이 표시되어 투명 효과가 보이지 않는다 — 이는 Windows와 동일한 요구사항이다.

---

## 5. 접근 수준 변경 요약

Phase 2, 3에서 확장 파일이 기존 `private` 헬퍼에 접근해야 한다.

| 파일 | 멤버 | 현재 | 변경 |
|------|------|------|------|
| `KSMacWindowBackend.swift` | `window(for:)` | `private` | `internal` |
| `KSMacWindowBackend.swift` | `runMain(_:_:)` | `private` | `internal` |
| `KSMacWindowBackend.swift` | `queryMain(_:_:)` | `private` | `internal` |

Windows에서도 `windowSync(for:)` / `queryMain` 등이 `internal`로 선언되어
`+Displays.swift`, `+Taskbar.swift`에서 사용된다.

---

## 6. 수정 대상 파일 요약

| 파일 | Phase | 변경 유형 | 변경 내용 |
|------|-------|----------|----------|
| `Sources/KalsaePlatformMac/KSMacPlatform.swift` | 1, 4 | **수정** | `runOnMain()`에서 `stateStore.load()` 추가, `KSMacDemoHost.init` 시그니처 변경, `installFileDropEmitter()` 추가, `setAllowExternalDrop` 스텁 → 실구현 교체 |
| `Sources/KalsaePlatformMac/AppKit/KSMacWindow.swift` | 1, 5 | **수정** | `init(config:restoredState:)` 복원 로직 추가, `rectIntersectsAnyScreen()` 헬퍼 추가, 투명 윈도우 활성화, `warnTransparentOnce` 관련 정적 멤버 삭제, `setContentView`에서 투명 배경 적용 |
| `Sources/KalsaePlatformMac/PAL/KSMacWindowBackend.swift` | 2, 3 | **수정** | `window(for:)`, `runMain`, `queryMain` 접근 수준 `private` → `internal` |
| `Sources/KalsaePlatformMac/PAL/KSMacWindowBackend+Displays.swift` | 2 | **신규** | `listDisplays()`, `currentDisplay()`, `displayInfo(from:maxY:isPrimary:)` 헬퍼 |
| `Sources/KalsaePlatformMac/PAL/KSMacWindowBackend+Taskbar.swift` | 3 | **신규** | `setTaskbarProgress()`, `setOverlayIcon()`, `KSDockProgressView` 내부 클래스 |
| `Sources/KalsaePlatformMac/WebKit/WKWebViewHost.swift` | 4, 5 | **수정** | `installFileDropHandler(_:)`, `setAllowExternalDrop(_:)`, `setTransparentBackground()` 추가, `KSFileDropOverlay` 내부 클래스 추가 |

---

## 7. 스코프 외 (향후 검토)

- macOS `NSVisualEffectView` 백드롭 효과 (Mica/Acrylic 대응)
- Display Enumeration / Taskbar 관련 유닛 테스트 추가 (`KSMacDisplaysTests.swift`)
- macOS CI 파이프라인 설정 (`.github/workflows/`)
- `AGENTS.md` §5 macOS 섹션에 투명/Dock progress/Display 지원 반영
- `setTaskbarProgress`와 `setOverlayIcon` 동시 사용 시 `contentView` 병합 전략
- `WKWebView` 커스텀 드래그 이벤트 propagation 최적화

---

## 8. 검증 계획 (수동)

1. `swift build` (macOS) — 신규 파일 포함 컴파일 성공 확인
2. `swift test --filter "KSMacPlatform"` — 기존 테스트 회귀 없음

기능별 수동 확인:

| Phase | 검증 시나리오 | 예상 결과 |
|---|---|---|
| 1 | 앱 시작 → 창을 (200,300) 위치에 800×600으로 리사이즈 → 종료 → 재시작 | 창이 (200,300) 위치에 800×600으로 복원됨 |
| 1 | 앱 시작 → 창 최대화 → 종료 → 재시작 | 창이 최대화 상태로 복원됨 |
| 1 | 앱 시작 → 창 전체화면 → 종료 → 재시작 | 창이 전체화면으로 복원됨 |
| 1 | 외부 모니터 연결 시 창 이동 → 모니터 분리 → 재시작 | 기본 위치로 폴백 (화면 밖 방지) |
| 2 | `listDisplays()` 호출 (데스크톱 + 외부 모니터) | 두 모니터 정보 반환, `isPrimary` 올바름, 좌표 top-left 원점 |
| 2 | `currentDisplay(handle)` 호출 | 해당 윈도우가 위치한 모니터 정보 반환 |
| 3 | `setTaskbarProgress(.normal(0.5))` 호출 | Dock 아이콘에 50% 진행률 바 표시 |
| 3 | `setTaskbarProgress(.error(0.7))` 호출 | Dock에 70% 빨간 바 표시 |
| 3 | `setTaskbarProgress(.none)` 호출 | Dock 아이콘 원래 상태 복원 |
| 3 | `setOverlayIcon(handle, iconPath: "icon.png", description: "3")` | Dock에 오버레이 + "3" 뱃지 |
| 4 | Finder에서 .txt 파일을 앱 윈도우로 드래그 진입 | `__ks.file.drop` event `kind: "enter"` 발생 |
| 4 | Finder에서 파일을 앱 윈도우에 드롭 | `kind: "drop"`, `paths` 배열에 절대경로 포함 |
| 4 | Finder에서 드래그 후 윈도우 밖으로 이동 | `kind: "leave"` 발생 |
| 5 | `transparent: true` 설정으로 앱 시작 | 투명 윈도우 렌더링, 데스크톱 배경 보임 |
| 5 | 투명 윈도우에서 웹 콘텐츠 `background: #fff` | 흰 배경으로 표시 (투명 효과 무효화) |
