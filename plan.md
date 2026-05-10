# Kalsae 아키텍처 구조 분석 보고서 (잔여 작업)

> 작성일: 2026-05-09
> 분석자: Cline (Architecture Review)
> 최종 업데이트: 2026-05-09 — 완료 항목 제거

---

## 0. 진행 현황

### ✅ 완료된 작업

| # | 문제 | 산출물 |
|---|------|--------|
| 2 | DemoHost 인터페이스의 비공식 프로토콜 | [Sources/KalsaeCore/PAL/KSDemoHost.swift](Sources/KalsaeCore/PAL/KSDemoHost.swift) — 8개 프로토콜 정의 (기본 + 플랫폼별 확장) |
| 4 | AnyPlatformHost의 조건부 컴파일 누수 | [Sources/Kalsae/KSDemoHostFactory.swift](Sources/Kalsae/KSDemoHostFactory.swift) — 호스트 생성 팩토리 |
| 1 | 부팅 로직의 플랫폼별 중복 | [Sources/KalsaeCore/PAL/KSBootOrchestrator.swift](Sources/KalsaeCore/PAL/KSBootOrchestrator.swift) — 5플랫폼 공통 결정 로직 단일화 |
| — | **Phase 1.3** — DemoHost 프로토콜 채택 + `AnyPlatformHost` 제거 | 5 호스트 모두 `: KSDemoHost` 채택, `KSApp.host`를 `any KSDemoHost`로 단순화, `AnyPlatformHost.swift` 삭제 |

> ✅ Phase 1.3 완료: `KSApp.init` 의 5-case switch 제거, `quit()` 단일화, `KSDemoHostFactory` 가 `any KSDemoHost` 반환.

### ❌ 미완료 작업 — 본 문서의 대상

| # | 문제 | 심각도 | 영향 범위 |
|---|------|--------|-----------|
| 1 | **부팅 로직의 플랫폼별 중복** (Massive Duplication) | 🔴 High | 5개 플랫폼 × 300+라인 |
| 3 | **KSPlatform의 Store-Through Property 중복** (Boilerplate) | 🟡 Medium | 5개 플랫폼 × 10개 백엔드 |
| 5 | **IPC 브리지 생성 패턴의 플랫폼별 분산** (Scattered Construction) | 🟢 Low | 각 플랫폼의 Bridge/WKWebViewHost/GtkBridge 등 |

---

## 1. 상세 분석

### 🔴 문제 1: 부팅 로직의 플랫폼별 중복 (Critical)

**현황:**
`KSApp.boot()` (686라인)와 각 플랫폼의 `runOnMain()` (`KSMacPlatform` 533라인, `KSLinuxPlatform` 646라인, `KSiOSPlatform` 279라인, `KSWindowsPlatform`의 `runOnMain`도 유사) 사이에 **대규모 중복**이 존재함.

**중복되는 로직:**
- `selectWindow(from:)` — 모든 플랫폼에 동일한 구현
- `decideServingMode(...)` — 모든 플랫폼에 동일한 구현
- `resolveStartURL(...)` — 모든 플랫폼에 동일한 구현
- `cspInjectionScript(_:)` — 모든 플랫폼에 동일한 구현
- `isDirectory(_:)` / `isRemoteURL(_:)` — 모든 플랫폼에 동일한 구현
- `commandRegistry.setAllowlist()` / `setRateLimit()` — 모든 플랫폼에 동일
- `stateStore` 생성 및 `saveSink` 등록 패턴 — 3개 플랫폼에서 유사
- `autostartBackend` / `deepLinkBackend` 생성 — 모든 플랫폼에 유사
- `registerBuiltinCommands(...)` 호출 — 모든 플랫폼에 유사

**영향:**
- 신규 플랫폼 추가 시 500~600라인의 보일러플레이트 필요
- 버그 수정 시 5개 파일을 동시에 수정해야 함 (실제로 `resolveExternalConfigOverride`는 `KSApp.swift`에만 있고 플랫폼 `runOnMain`에는 없음 — 불일치)
- `KSApp.boot()`와 `KSMacPlatform.runOnMain()`은 **동일한 부팅을 수행하는 두 개의 진입점**으로, 어느 쪽이 사용되는지 혼란스러움

**권장 리팩터:**
```
KalsaeCore/
  KSBootOrchestrator.swift  ← 공통 부팅 로직을 여기로 추출
    - selectWindow()
    - decideServingMode()
    - resolveStartURL()
    - cspInjectionScript()
    - isDirectory() / isRemoteURL()
    - createAutostartBackend()
    - createDeepLinkBackend()
    - setupStateStore()
    - registerBuiltinCommands()
```

---

### 🟡 문제 3: KSPlatform의 Store-Through Property 중복 (Boilerplate)

**현황:**
5개 플랫폼 모두 `KSPlatform` 프로토콜을 채택하면서 다음과 같은 패턴이 반복됨:

```swift
// KSMacPlatform.swift
public var windows: any KSWindowBackend { _windows }
public var dialogs: any KSDialogBackend { _dialogs }
public var tray: (any KSTrayBackend)? { _tray }
public var menus: any KSMenuBackend { _menus }
// ... 10개 백엔드 × 5개 플랫폼 = 50줄의 순수 보일러플레이트

private let _windows: KSMacWindowBackend
private let _dialogs: KSMacDialogBackend
// ... 또 10줄

// init()에서 또 10줄 할당
```

**영향:**
- 신규 플랫폼 추가 시 30~40라인의 단순 반복 코드 작성 필요
- 백엔드 타입이 변경되면 5개 파일 수정 필요
- `nonisolated(unsafe) var _autostart` / `_deepLink` 패턴이 플랫폼마다 제각각

**권장 리팩터:**
```swift
// KalsaeCore/PAL/ KSPlatformComponents.swift
public struct KSPlatformComponents: Sendable {
    public var windows: any KSWindowBackend
    public var dialogs: any KSDialogBackend
    public var tray: (any KSTrayBackend)?
    public var menus: any KSMenuBackend
    public var notifications: any KSNotificationBackend
    public var shell: (any KSShellBackend)?
    public var clipboard: (any KSClipboardBackend)?
    public var accelerators: (any KSAcceleratorBackend)?
    public var autostart: (any KSAutostartBackend)?
    public var deepLink: (any KSDeepLinkBackend)?

    public init(
        windows: any KSWindowBackend,
        dialogs: any KSDialogBackend,
        tray: (any KSTrayBackend)? = nil,
        // ...
    ) { ... }
}

// 플랫폼 구현:
public final class KSMacPlatform: KSPlatform, @unchecked Sendable {
    public let components: KSPlatformComponents
    public var windows: any KSWindowBackend { components.windows }
    // ... 자동 생성 가능 (Sourcery / macro)
}
```

---

### 🟢 문제 5: IPC 브리지 생성 패턴의 플랫폼별 분산

**현황:**
각 플랫폼의 DemoHost가 IPC 브리지를 생성하는 방식이 제각각:
- `WebView2Bridge` (Windows) — C++ shim + Swift 콜백
- `WKBridge` (macOS/iOS) — WKUserContentController message handler
- `GtkBridge` (Linux) — JavaScriptCore evaluation
- `KSAndroidBridge` (Android) — JNI bridge

**영향:**
- 브리지 생성 로직이 DemoHost init에 하드코딩됨
- 브리지 타입이 `associatedtype`으로 추상화되지 않음
- `AnyPlatformHost`가 브리지에 접근할 방법이 없음

---

## 2. 아키텍처 다이어그램 (현재 vs 제안)

### 현재 구조 (남은 중복 영역)
```
KSApp.boot() [686 lines, #if os() hell]
  ├── selectWindow() [중복 ×5]
  ├── decideServingMode() [중복 ×5]
  ├── resolveStartURL() [중복 ×5]
  ├── cspInjectionScript() [중복 ×5]
  ├── createHost() [✅ KSDemoHostFactory로 1곳 집중]
  ├── setupSecurity() [중복 ×3~5]
  ├── registerBuiltinCommands() [중복 ×5]
  └── createBackends() [중복 ×5]

KSMacPlatform.runOnMain() [533 lines, 동일 로직 중복]
KSLinuxPlatform.runOnMain() [646 lines, 동일 로직 중복]
KSiOSPlatform.runOnMain() [279 lines, 동일 로직 중복]
KSWindowsPlatform.runOnMain() [유사, 내부에 runOnMain 존재]
```

### 제안 구조
```
KSApp.boot() [~150 lines, thin coordinator]
  └── KSBootOrchestrator.bootstrap() [~300 lines, single source of truth]
        ├── selectWindow() [1 place]
        ├── decideServingMode() [1 place]
        ├── resolveStartURL() [1 place]
        ├── cspInjectionScript() [1 place]
        ├── KSDemoHostFactory.makeHost() [✅ 완료]
        ├── setupSecurity() [1 place]
        ├── registerBuiltinCommands() [1 place]
        └── createBackends() [1 place]

KSMacPlatform.runOnMain() [~50 lines, platform-specific only]
KSLinuxPlatform.runOnMain() [~50 lines, platform-specific only]
KSiOSPlatform.runOnMain() [~50 lines, platform-specific only]
```

---

## 3. 우선순위 및 권장 작업 순서

| 순위 | 작업 | 예상 공수 | 리스크 |
|------|------|-----------|--------|
| 1 | **KSBootOrchestrator 추출** (문제 1) | 3-5일 | 높음 — `KSApp.boot()`와 플랫폼 `runOnMain()`의 로직 통합 |
| 2 | **KSPlatformComponents 도입** (문제 3) | 1-2일 | 낮음 — Store-through property 제거 |
| 3 | **IPC 브리지 프로토콜 추상화** (문제 5) | 2-3일 | 중간 — `KSBridge` 프로토콜 정의 |

> **참고:** Phase 1.3 (DemoHost 프로토콜 채택 선언) 는 Swift 6 actor 격리 호환성 재검토 후 KSBootOrchestrator 진행 시 재시도 권장.

---

## 4. 결론

Kalsae는 **레이어드 아키텍처 원칙**을 잘 지키고 있으며, 모듈 간 의존성 방향도 올바르다. 1차 리팩터링(KSDemoHostFactory + KSDemoHost 프로토콜)으로 **신규 플랫폼 온보딩의 인터페이스 모호성과 호스트 생성 분산 문제**는 해결되었다.

**남은 시급한 개선:**
1. **KSBootOrchestrator 추출** — 부팅 로직의 단일 진실 공급원 확보 (가장 큰 효과)
2. **KSPlatformComponents 도입** — 백엔드 보일러플레이트 감소

이 두 가지가 완료되면 신규 플랫폼 추가 비용은 **~600라인 → ~50라인**으로 줄어들며, 버그 수정 시 **5개 파일이 아닌 1개 파일**만 수정하면 된다.
