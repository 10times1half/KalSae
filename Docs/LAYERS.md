# Kalsae 시스템 레이어 구조

레포 전체를 의존 방향(위→아래) 기준으로 6계층으로 나눈다. 신규 코드는 자신이
속한 레이어의 책임 범위와 경계 규칙을 따라야 한다.

> 관련 문서: [ARCHITECTURE.md](ARCHITECTURE.md), [AGENTS.md](../AGENTS.md)

---

## 개요

```
┌──────────────────────────────────────────────────────────────┐
│ L1. 개발자 도구 (CLI / 빌드)                                  │
│     사용자가 터미널에서 실행. 산출물 생성·템플릿 처리          │
├──────────────────────────────────────────────────────────────┤
│ L2. Public 파사드 (사용자 API)                                │
│     사용자가 코드에서 import. 진입점·플랫폼 선택               │
├──────────────────────────────────────────────────────────────┤
│ L3. 코어 / 계약 (Contracts & Services)                        │
│     플랫폼 독립. PAL 프로토콜·IPC·Config·Assets               │
├──────────────────────────────────────────────────────────────┤
│ L4. PAL 구현 (OS별 백엔드)                                    │
│     Win/Mac/Linux/iOS/Android. 코어 프로토콜 구현              │
├──────────────────────────────────────────────────────────────┤
│ L5. 네이티브 글루 (C/C++/JNI/Kotlin shim)                     │
│     OS SDK ↔ Swift ABI/메모리 경계                            │
├──────────────────────────────────────────────────────────────┤
│ L6. 사용자 자산 (프론트엔드 / 샘플)                            │
│     HTML/JS/CSS, 데모, Android Gradle 샘플                    │
└──────────────────────────────────────────────────────────────┘
```

---

## L1. 개발자 도구 (CLI / 빌드)

**역할**: 프로젝트 생성, 개발 서버, 패키징, 바인딩 생성. 호스트 OS에서만 동작.

| 모듈 | 위치 | 책임 |
|---|---|---|
| `KalsaeCLI` (executable) | [Sources/KalsaeCLI/](../Sources/KalsaeCLI/) | `kalsae` 명령어 진입점 |
| Commands | [Sources/KalsaeCLI/Commands/](../Sources/KalsaeCLI/Commands/) | `new`, `dev`, `build`, `generate` 서브커맨드 |
| `KalsaeCLICore` (Support) | [Sources/KalsaeCLI/Support/](../Sources/KalsaeCLI/Support/) | Packager, BindingsGenerator, ProjectTemplate, Shell |
| Scripts | [Scripts/](../Scripts/) | `fetch-webview2.ps1`, `format.ps1` 등 보조 스크립트 |

**경계 규칙**: PAL을 import하지 않음. 산출물을 "파일"로만 다룸.

---

## L2. Public 파사드 (사용자 API)

**역할**: 사용자가 직접 호출하는 진입점. 런타임에 플랫폼 PAL을 선택해 부팅.

| 모듈 | 위치 | 핵심 타입 |
|---|---|---|
| `Kalsae` | [Sources/Kalsae/](../Sources/Kalsae/) | `KSApp`, `KSApp+Boot`, `KSApp+UI`, `KSApp+SingleInstance`, `KSApp+Plugins`, `KSDemoHostFactory` |
| `KalsaeMacros` | [Sources/KalsaeMacros/](../Sources/KalsaeMacros/) | `@KSCommand` 매크로 선언부 (소비자 측) |
| `KalsaeMacrosPlugin` | [Sources/KalsaeMacrosPlugin/](../Sources/KalsaeMacrosPlugin/) | SwiftSyntax 매크로 구현 (컴파일러 플러그인) |

**경계 규칙**: `Kalsae`는 `KalsaeCore`만 직접 의존. 구체 PAL 호스트는 `#if os(...)` +
`KSDemoHostFactory.makeHost()`로 런타임에 선택되며 `any KSDemoHost`로 다뤄진다.

---

## L3. 코어 / 계약

**역할**: 플랫폼 독립 로직과 PAL이 구현해야 할 프로토콜.

| 영역 | 위치 | 내용 |
|---|---|---|
| 빌드 메타 | [Sources/KalsaeCore/](../Sources/KalsaeCore/) (`KSBuildMode`, `KSVersion`) | 모드/버전 상수 |
| PAL 계약 | [Sources/KalsaeCore/PAL/](../Sources/KalsaeCore/PAL/) | 윈도우/메뉴/트레이/다이얼로그/노티/클립보드 등 백엔드 프로토콜 |
| IPC | [Sources/KalsaeCore/IPC/](../Sources/KalsaeCore/IPC/) | `KSCommandRegistry`, 메시지 인코딩, 빌트인 커맨드 |
| Config | [Sources/KalsaeCore/Config/](../Sources/KalsaeCore/Config/) | `Kalsae.json` 스키마, 로더 |
| Assets | [Sources/KalsaeCore/Assets/](../Sources/KalsaeCore/Assets/) | `KSAssetCache`, `KSAssetResolver`, `ks://app/` 자산 서빙 |
| Errors | [Sources/KalsaeCore/Error/](../Sources/KalsaeCore/Error/) | `KSError`, `KSErrorCode` (typed throws) |
| Logging | [Sources/KalsaeCore/Logging/](../Sources/KalsaeCore/Logging/) | 구조화 로거 |
| Plugin 호스트 | [Sources/KalsaeCore/Plugin/](../Sources/KalsaeCore/Plugin/) | 플러그인 인터페이스 |
| Plugin 구현 | [Sources/KalsaePluginProcess/](../Sources/KalsaePluginProcess/) | 별도 모듈로 제공되는 표준 플러그인(Process) |

**경계 규칙**: OS API 직접 호출 금지. 모든 플랫폼 의존성은 프로토콜로 추상화.

---

## L4. PAL 구현 (OS별 백엔드)

**역할**: 코어 프로토콜을 OS SDK로 구현. 플랫폼당 1개 모듈.

| 플랫폼 | 모듈 | 주요 디렉터리 |
|---|---|---|
| Windows | [Sources/KalsaePlatformWindows/](../Sources/KalsaePlatformWindows/) | `Win32/`, `WebView2/`, `PAL/` |
| macOS | [Sources/KalsaePlatformMac/](../Sources/KalsaePlatformMac/) | `AppKit/`, `WebKit/`, `PAL/` |
| Linux | [Sources/KalsaePlatformLinux/](../Sources/KalsaePlatformLinux/) | `Gtk/`, `PAL/` |
| iOS | [Sources/KalsaePlatformIOS/](../Sources/KalsaePlatformIOS/) | `UIKit/`, `WebKit/`, `PAL/` |
| Android | [Sources/KalsaePlatformAndroid/](../Sources/KalsaePlatformAndroid/) | `JNI/`(Swift측), `WebView/`, `PAL/` |

각 모듈에 진입점 `KS{Platform}Platform.swift`와 데모 호스트(`KS{Platform}DemoHost.swift`)가 위치.

**경계 규칙**: 다른 PAL 모듈을 import하지 않음. 공통 로직이 필요하면 L3로 승격.

---

## L5. 네이티브 글루 (C / C++ / JNI shim)

**역할**: Swift에서 직접 부르기 어려운 OS SDK를 ABI/메모리/스레드 경계에서 어댑팅.

| 글루 | 위치 | 용도 |
|---|---|---|
| WebView2 C++ shim | [Sources/CKalsaeWV2/](../Sources/CKalsaeWV2/) | WebView2 COM/WinRT → C ABI |
| GTK C shim | [Sources/CKalsaeGtk/](../Sources/CKalsaeGtk/) | GTK4 콜백/시그널 → Swift |
| GTK4 systemLibrary | [Sources/CGtk4/](../Sources/CGtk4/) | pkg-config modulemap |
| WebKitGTK systemLibrary | [Sources/CWebKitGTK/](../Sources/CWebKitGTK/) | pkg-config modulemap |
| Android JNI (Swift측) | [Sources/KalsaePlatformAndroid/JNI/](../Sources/KalsaePlatformAndroid/JNI/) | `KS_android_*` C 함수 — JVM 진입점 |

**경계 규칙**: 비즈니스 로직 금지. 메모리 소유권(`KSWV2_Alloc`/`Free`)·콜백 변환만.

---

## L6. 사용자 자산 / 샘플 / 문서

**역할**: 프레임워크 외부에 위치하는 사용자 코드와 참조 자료.

| 영역 | 위치 | 내용 |
|---|---|---|
| 데모 앱 | [Sources/KalsaeDemo/](../Sources/KalsaeDemo/) | `kalsae-demo` 실행 파일, 프론트엔드 자산(`Resources/`, `dist-bench/`) |
| 예제 설정 | [Examples/](../Examples/) | `kalsae.sample.json` |
| Android 샘플 | [Samples/KalsaeAndroidSample/](../Samples/KalsaeAndroidSample/) | Gradle 프로젝트 (Kotlin 호스트 참조 구현) |
| 테스트 | [Tests/](../Tests/) | `KalsaeCoreTests`, `KalsaeCLITests`, `KalsaeMacrosTests`, `KalsaePlatform*Tests`, `KalsaePluginProcessTests` (각 L3·L4 모듈과 1:1 대응) |
| 문서 | [Docs/](.), [README.md](../README.md), [AGENTS.md](../AGENTS.md), [plan.md](../plan.md) | 아키텍처·CLI·IPC·SECURITY·RFC |

---

## 의존성 다이어그램

```
[L1 CLI] ──생성──▶ [L6 사용자자산]
   │
   │ (실행시 사용자 앱이 링크)
   ▼
[L2 Kalsae(Public)] ──▶ [L3 KalsaeCore]
        │                      ▲
        │ #if os(...)          │ 프로토콜 채택
        ▼                      │
[L4 KalsaePlatform{Win,Mac,Linux,iOS,Android}]
        │
        │ C/JNI 호출
        ▼
[L5 CKalsae{WV2,Gtk}, CGtk4, CWebKitGTK, JNI]
        │
        ▼
   [OS SDK]
```

---

## 핵심 불변식

1. **단방향 의존**: L1·L2·L4 → L3. L4 → L5. 역방향/횡단 금지.
2. **PAL 간 격리**: L4 모듈끼리 서로 import 금지. 공통 로직은 L3로 승격.
3. **Public 노출 모듈**(L2, L3, L4)은 `public import` 사용
   (`InternalImportsByDefault` 패키지 옵션 때문).
4. **글루는 ABI만** — 비즈니스 로직은 항상 Swift(L4)로 끌어올림.
5. **테스트는 같은 레이어**에서 검증 — `Tests/Kalsae{Module}Tests`가 모듈과 1:1.

_🇰🇷 6계층 단방향 의존. CLI는 PAL 모름, PAL끼리 모름, 글루는 ABI만._
