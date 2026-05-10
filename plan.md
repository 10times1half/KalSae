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
| 3 | **KSPlatform의 Store-Through Property 중복** (Boilerplate) | 🟡 Medium | 5개 플랫폼 × 10개 백엔드 |
| 5 | **IPC 브리지 생성 패턴의 플랫폼별 분산** (Scattered Construction) | 🟢 Low | 각 플랫폼의 Bridge/WKWebViewHost/GtkBridge 등 |

---

## 1. 상세 분석

###  문제 3: KSPlatform의 Store-Through Property 중복 (Boilerplate)

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

## 2. 아키텍처 다이어그램 (현재)

```
KSApp.boot() [thin coordinator]
  └── KSBootOrchestrator.bootstrap() [✅ 단일 진실 공급원]
        ├── selectWindow() [1 place]
        ├── decideServingMode() [1 place]
        ├── resolveStartURL() [1 place]
        ├── cspInjectionScript() [1 place]
        ├── KSDemoHostFactory.makeHost() [✅ 완료]
        ├── setupSecurity() [1 place]
        ├── registerBuiltinCommands() [1 place]
        └── createBackends() [1 place]

KS{Mac,Linux,iOS,Windows,Android}Platform.runOnMain()
  └── 플랫폼 고유 메시지 루프/라이프사이클만 담당.
```

---

## 3. 우선순위 및 권장 작업 순서

| 순위 | 작업 | 예상 공수 | 리스크 |
|------|------|-----------|--------|
| 1 | **KSPlatformComponents 도입** (문제 3) | 1-2일 | 낮음 — Store-through property 제거 |
| 2 | **IPC 브리지 프로토콜 추상화** (문제 5) | 2-3일 | 중간 — `KSBridge` 프로토콜 정의 |

---

## 4. 결론

Kalsae는 **레이어드 아키텍처 원칙**을 잘 지키고 있으며, 모듈 간 의존성 방향도 올바르다. 1차 리팩터링(KSDemoHostFactory + KSDemoHost 프로토콜 + KSBootOrchestrator)으로 **신규 플랫폼 온보딩의 인터페이스 모호성, 호스트 생성 분산, 부팅 로직 중복 문제**는 해결되었다.

**남은 개선:**
1. **KSPlatformComponents 도입** — 백엔드 보일러플레이트 감소
2. **IPC 브리지 프로토콜 추상화** — `KSBridge` 프로토콜로 명시화
