# Kalsae 아키텍처 구조 분석 보고서 (잔여 작업)

> 작성일: 2026-05-09
> 분석자: Cline (Architecture Review)
> 최종 업데이트: 2026-05-15 — 문제 5(KSBridge) 완료 반영, 모든 1차 리팩터링 항목 해결

---

## 0. 진행 현황

### ✅ 완료된 작업

| # | 문제 | 산출물 |
|---|------|--------|
| 2 | DemoHost 인터페이스의 비공식 프로토콜 | [Sources/KalsaeCore/PAL/KSDemoHost.swift](Sources/KalsaeCore/PAL/KSDemoHost.swift) — 8개 프로토콜 정의 (기본 + 플랫폼별 확장) |
| 4 | AnyPlatformHost의 조건부 컴파일 누수 | [Sources/Kalsae/KSDemoHostFactory.swift](Sources/Kalsae/KSDemoHostFactory.swift) — 호스트 생성 팩토리 |
| 1 | 부팅 로직의 플랫폼별 중복 | [Sources/KalsaeCore/PAL/KSBootOrchestrator.swift](Sources/KalsaeCore/PAL/KSBootOrchestrator.swift) — 5플랫폼 공통 결정 로직 단일화 |
| — | **Phase 1.3** — DemoHost 프로토콜 채택 + `AnyPlatformHost` 제거 | 5 호스트 모두 `: KSDemoHost` 채택, `KSApp.host`를 `any KSDemoHost`로 단순화, `AnyPlatformHost.swift` 삭제 |
| 3 | **KSPlatform Store-Through Property 중복** (Boilerplate) | [Sources/KalsaeCore/PAL/KSPlatformComponents.swift](Sources/KalsaeCore/PAL/KSPlatformComponents.swift) — `KSPlatformComponents` 구조체 + `KSPlatformComponentsProvider` 프로토콜로 5개 플랫폼 모두 10개 백엔드 프로퍼티 자동 위임 |
| — | **KSPluginContext.quit()** (RFC-007 Phase 1) | [Sources/KalsaeCore/Plugin/KSPlugin.swift](Sources/KalsaeCore/Plugin/KSPlugin.swift) — 프로토콜에 `func quit()` 추가, `DefaultPluginContext`가 `KSApp.quit()`에 위임 |
| 5 | **IPC 브리지 프로토콜 추상화** | [Sources/KalsaeCore/PAL/KSBridge.swift](Sources/KalsaeCore/PAL/KSBridge.swift) — `@MainActor public protocol KSBridge` 정의 (windowLabel / onEvent / install / emit), 5개 플랫폼 브리지(`WebView2Bridge`, `WKBridge`, `GtkBridge`, `KSiOSBridge`, `KSAndroidBridge`) 모두 채택, `KSDemoHost.bridge: any KSBridge` 노출 |

> ✅ Phase 1.3 완료: `KSApp.init` 의 5-case switch 제거, `quit()` 단일화, `KSDemoHostFactory` 가 `any KSDemoHost` 반환.

### ❌ 미완료 작업 — 본 문서의 대상

_없음. 본 문서가 다루던 1차 아키텍처 리팩터링은 모두 완료되었다. 신규 잔여 작업은 RFC-001(Updater), RFC-007(Android 안정화), RFC-008(스토어 배포) 등 RFC 문서를 참조한다._

---

## 1. 상세 분석

### 🟢 문제 5: IPC 브리지 프로토콜 추상화 — ✅ 완료

**해결책:**
`Sources/KalsaeCore/PAL/KSBridge.swift`에 `@MainActor public protocol KSBridge: AnyObject, Sendable` 정의:
- `var windowLabel: String { get }`
- `var onEvent: (@MainActor (String, Data?) -> Void)? { get set }`
- `func install() throws(KSError)`
- `func emit(event:payload:) throws(KSError)`

5개 플랫폼 브리지(`WebView2Bridge`, `WKBridge`, `GtkBridge`, `KSiOSBridge`, `KSAndroidBridge`)가 모두 채택하며 `windowLabel`을 `public`으로 노출한다. `KSDemoHost` 프로토콜에 `var bridge: any KSBridge { get }`를 추가하여 KalsaeCore 레벨 코드가 플랫폼 분기 없이 브리지에 접근할 수 있다.

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

_본 문서가 다루던 1차 아키텍처 리팩터링은 모두 완료되었다. 다음 단계 작업은 RFC 문서를 참조:_
- [Docs/RFCs/RFC-001-updater.md](Docs/RFCs/RFC-001-updater.md) — 데스크톱 자동 업데이트
- [Docs/RFCs/RFC-007-android-release.md](Docs/RFCs/RFC-007-android-release.md) — Android preview → stable
- [Docs/RFCs/RFC-008-store-distribution.md](Docs/RFCs/RFC-008-store-distribution.md) — 스토어 배포

---

## 4. 결론

Kalsae는 **레이어드 아키텍처 원칙**을 잘 지키고 있으며, 모듈 간 의존성 방향도 올바르다. 1차 리팩터링(KSDemoHostFactory + KSDemoHost 프로토콜 + KSBootOrchestrator + KSPlatformComponents + KSBridge)으로 **신규 플랫폼 온보딩의 인터페이스 모호성, 호스트 생성 분산, 부팅 로직 중복, 백엔드 보일러플레이트, IPC 브리지 추상화 부재** 문제는 모두 해결되었다.

**남은 개선:**
1. **IPC 브리지 프로토콜 추상화** — `KSBridge` 프로토콜로 명시화
