# RFC-003 — KalsaeCore 모듈 코드 품질 검토 보고서 (Code Review)

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-09 |
| 영향 범위 | `KalsaeCore` 전 모듈 (IPC, Config, Assets, PAL, Plugin, Error, Logging) |
| 관련 | `AGENTS.md`, `KSIPCBridgeCore.swift`, `KSCommandRegistry.swift`, `KSBuiltinCommands+Window.swift`, `KSPlatform.swift`, `KSWindowBackend.swift`, `KSAssetCache.swift`, `KSFSScope+Match.swift`, `KSUserDataPathValidator.swift`, `KSWindowStateStore.swift` |

---

## 1. 동기 (Motivation)

KalsaeCore는 Kalsae 프레임워크의 핵심 모듈로, IPC 통신, 설정 관리, 자산 캐싱, 플랫폼 추상화 계층(PAL), 플러그인 시스템, 에러 처리, 로깅 등 프레임워크 전반의 기반을 담당한다.

본 문서는 KalsaeCore 모듈의 **37개 파일, 약 4,500라인**의 Swift 소스 코드를 Swift 6.0 모범 사례, AGENTS.md 코딩 컨벤션, 보안 원칙, 동시성 모델 관점에서 엄격히 검토한 결과를 기록한다.

---

## 2. 검토 범위 (Scope)

| 영역 | 파일 수 | 주요 파일 |
|------|---------|-----------|
| Error | 1 | `KSError.swift` |
| Logging | 1 | `KSLog.swift` |
| IPC Core | 3 | `KSCommandRegistry.swift`, `KSIPCBridgeCore.swift`, `KSInvocationContext.swift`, `KSWindowEmitHub.swift` |
| IPC BuiltinCommands | 10 | `KSBuiltinCommands.swift`, `+Window`, `+Shell`, `+Clipboard`, `+Notification`, `+Dialog`, `+FS`, `+HTTP`, `+Autostart`, `+DeepLink`, `+App` |
| Config | 11 | `KSConfig.swift`, `KSWebViewOptions.swift`, `KSFSScope.swift`, `KSFSScope+Match.swift`, `KSHTTPScope.swift`, `KSShellScope.swift`, `KSNotificationScope.swift`, `KSDeepLinkConfig.swift`, `KSTrayConfig.swift`, `KSUserDataPathValidator.swift`, `KSWebViewArgsValidator.swift` |
| Assets | 5 | `KSAssetCache.swift`, `KSAssetResolver.swift`, `KSAssetPackager.swift`, `KSAssetManifest.swift`, `KSAssetSource.swift` |
| PAL Contracts | 14 | `KSPlatform.swift`, `KSWindowBackend.swift`, `KSWebViewBackend.swift`, `KSMenuBackend.swift`, `KSTrayBackend.swift`, `KSDialogBackend.swift`, `KSClipboardBackend.swift`, `KSShellBackend.swift`, `KSNotificationBackend.swift`, `KSAcceleratorBackend.swift`, `KSAutostartBackend.swift`, `KSDeepLinkBackend.swift`, `KSSchemeHandler.swift`, `KSDisplay.swift`, `KSWindowStateStore.swift`, `KSDemoHost.swift`, `KSWebViewCapabilityReport.swift` |
| Plugin | 1 | `KSPlugin.swift` |
| 기타 | 2 | `KSBuildMode.swift`, `KSVersion.swift` |

---

## 3. 강점 (Strengths)

### 3.1 Typed throws 일관성

`async throws(KSError)`가 프로젝트 전체에 일관되게 적용되어 있다. AGENTS.md §4의 규칙을 완벽히 준수하며, `catch let e as KSError` 패턴이 필요한 곳(JSONEncoder + handler 혼합 throw 지점)에 정확히 사용되었다.

```swift
// KSBuiltinCommands.swift — 혼합 throw 지점의 올바른 처리
do {
    let out = try await handler(input)
    let encoded = try JSONEncoder().encode(out)
    return .success(encoded)
} catch let e as KSError {
    // 혼합 throw 지점 (JSONEncoder + handler(KSError)) — AGENTS §4 참조
    return .failure(e)
} catch {
    return .failure(KSError(code: .commandExecutionFailed, message: "\(error)"))
}
```

### 3.2 보안 중심 설계

다양한 보안 계층이 체계적으로 구현되어 있다:

- **`KSFSScope.permits()`** — `allow`/`deny` 이중 검증 + `$APP`/`$HOME`/`$DOCS`/`$TEMP` 플레이스홀더 확장
- **`KSWebViewArgsValidator`** — Chromium 위험 인자 블랙리스트 (`--no-sandbox`, `--disable-web-security`, `--remote-debugging-port` 등 11개)
- **`KSUserDataPathValidator`** — `..` 트래버설 차단 + 화이트리스트 기반 경로 검증
- **`KSHTTPScope`** — 기본 거부(default-deny) 정책, 호스트/스킴/메서드 레벨 게이팅
- **`KSCommandRegistry`** — allowlist + token-bucket rate limiter

### 3.3 동시성 모델

Swift 6.0의 동시성 기능을 적절히 활용하고 있다:

- `@MainActor` 격리가 필요한 곳(`KSIPCBridgeCore`, `KSWindowEmitHub`)에 정확히 적용
- `actor KSCommandRegistry` — 레지스트리 상태를 actor로 보호
- `Task.detached` + `hop` 패턴으로 IPC 디스패치를 백그라운드에서 처리
- `@TaskLocal`을 활용한 `KSInvocationContext.windowLabel` — 창 컨텍스트 전파

### 3.4 메모리/성능 최적화

- **`KSAssetCache`** — LRU 이중 연결 리스트 + `maxBytes`/`maxEntries` 이중 제한
- **`KSIPCBridgeCore.rawJSONBytes()`** — `JSONSerialization` 1단계로 `KSAnyJSON` 2단계 decode→encode 회피
- **`encodeForJS()`** — 수동 JSON 조립으로 중간 `Data` 할당 제거
- **`_sharedEncoder`** — `JSONEncoder` 인스턴스 재사용

### 3.5 코드 구조화

- 프로토콜 분할 (`KSWindowLifecycle` / `KSWindowGeometry` / `KSWindowState` → `KSWindowBackend` refinement)
- BuiltinCommands를 도메인별 파일로 분리 (Window, Shell, Clipboard, Notification, FS, HTTP, Dialog, Autostart, DeepLink, App)
- Config 타입들의 커스텀 `init(from:)`으로 JSON 필드 선택적 처리

---

## 4. 발견된 문제점 (Issues)

### 🔴 심각 (Critical)

#### Issue #1: `encodeForJS()` — 수동 JSON 직렬화의 안전성

**파일:** `Sources/KalsaeCore/IPC/KSIPCBridgeCore.swift` (lines 202-228)

**설명:**
`encodeForJS()`가 수동으로 JSON 문자열을 조립한다. `appendJSEscaped()`와 `appendJSEscapedRaw()`가 XSS 방지를 위해 `<\/` 이스케이프를 처리하지만, **`payload`가 이미 JSON 문자열이라고 가정하고 raw로 삽입**하는 방식(`appendJSEscapedRaw`)은 위험하다.

```swift
// line 216-218
if let payload = msg.payload, let s = String(data: payload, encoding: .utf8) {
    out.append(",\"payload\":")
    appendJSEscapedRaw(into: &out, s)
}
```

**영향:**
`payload`가 유효한 JSON이 아닌 경우(예: `KSAnyEncodable` 래핑 실패, 인코딩 버그 등), 잘못된 JSON이 생성되어 JS 파서를 혼란시킬 수 있다.

**권장 수정:**
- `JSONSerialization` + `JSONEncoder`를 사용한 정규 경로로 리팩토링
- 또는 payload가 항상 유효한 JSON임을 보장하는 단위 테스트 추가

---

#### Issue #2: `KSCommandRegistry.consumeToken()` — 부동소수점 정밀도

**파일:** `Sources/KalsaeCore/IPC/KSCommandRegistry.swift` (lines 36-50)

**설명:**
```swift
let seconds =
    Double(elapsed.components.seconds)
    + Double(elapsed.components.attoseconds) * 1e-18
```

`attoseconds`를 `Double`로 변환할 때 `1e-18`을 곱하면 매우 작은 값이지만, `Double`의 정밀도 한계(약 15-17 유효숫자)로 인해 `attoseconds`의 하위 비트가 손실된다.

**영향:**
이론적으로 rate limiter의 정밀도에 영향을 줄 수 있으나, 실용적 영향은 미미하다.

**권장 수정:**
`Duration`을 `TimeInterval`(초)으로 변환하는 표준 유틸리티 사용.

---

#### Issue #3: `KSAssetCache` — `@unchecked Sendable`의 NSLock 사용

**파일:** `Sources/KalsaeCore/Assets/KSAssetCache.swift` (line 19)

**설명:**
```swift
public final class KSAssetCache: @unchecked Sendable {
```

`NSLock`으로 동기화하는 것은 올바르지만, `@unchecked Sendable`은 컴파일러 검사를 우회한다.

**영향:**
향후 리팩토링 시 실수로 잠금 없는 코드 경로가 추가될 위험이 있다.

**권장 수정:**
`os_unfair_lock` 또는 `Mutex`(Swift 6.0)로 마이그레이션 고려.

---

### 🟡 주의 (Warning)

#### Issue #4: `KSIPCBridgeCore.handleInbound()` — `Task.detached`에서 `weak self`

**파일:** `Sources/KalsaeCore/IPC/KSIPCBridgeCore.swift` (line 109)

**설명:**
```swift
Task.detached { [weak self] in
    let result = await KSInvocationContext.$windowLabel.withValue(wl) {
        await registry.dispatch(name: name, args: args)
    }
    hop {
        self?.sendResponse(id: id, result: result)
    }
}
```

`weak self`로 인해 `KSIPCBridgeCore`가 해제된 후에도 `Task.detached`는 계속 실행된다. `registry.dispatch()`는 `self` 없이도 실행되지만, 응답을 보낼 수 없어 JS 측이 영원히 대기하게 된다.

**영향:**
메모리 해제 타이밍에 따라 JS 호출이 응답 없이 타임아웃될 수 있다.

**권장 수정:**
`strong self`를 캡처하거나, 적어도 로그를 남기는 것이 좋다.

---

#### Issue #5: `KSBuiltinCommands+Window.swift` — `MainActor.run` 클로저 컨텍스트 예외

**파일:** `Sources/KalsaeCore/IPC/KSBuiltinCommands+Window.swift` (lines 182-196)

**설명:**
```swift
let r: Result<Void, KSError> = await MainActor.run {
    do {
        try KSWindowEmitHub.shared.emit(...)
        return .success(())
    } catch {
        return .failure(
            error as? KSError ?? KSError(code: .internal, message: "\(error)"))
    }
}
```

`MainActor.run` 같은 클로저 컨텍스트에서는 typed throw 정보가 지워질 수 있어, `catch`의 `error`가 `Error`로 바인딩된다. 따라서 현재의
`error as? KSError ?? KSError(...)` 패턴은 AGENTS.md §4 예외 규칙에 부합한다.

**영향:**
실제 버그는 아니며, 컨벤션 위반도 아니다.

**권장 수정:**
현 구현 유지 (변경 없음).

---

#### Issue #6: `KSFSScope.glob()` — `NSRegularExpression` 스레드 안전성

**파일:** `Sources/KalsaeCore/Config/KSFSScope+Match.swift` (line 116)

**설명:**
```swift
guard let regex = try? NSRegularExpression(pattern: rx, options: opts) else {
    return false
}
```

`NSRegularExpression`은 문서상 스레드 안전하지만(immutable), 매번 패턴을 컴파일하는 것은 비효율적이다. `glob()`은 `permits()` 호출마다 여러 번 호출될 수 있다.

**영향:**
파일 시스템 접근이 많은 시나리오에서 성능 저하 가능성.

**권장 수정:**
캐싱 계층을 도입하거나, `Regex`(Swift 5.7+)로 마이그레이션 고려.

---

#### Issue #7: `KSUserDataPathValidator.expandEnvVars()` — `$VAR` 파싱의 모호성

**파일:** `Sources/KalsaeCore/Config/KSUserDataPathValidator.swift` (lines 115-143)

**설명:**
`$VAR` 토큰 파싱이 영숫자/언더스코어 문자를 greedy하게 소비한다. `${VAR}` 중괄호 문법을 지원하지 않는다.

**영향:**
`${HOME}_suffix` 같은 POSIX 표준 패턴이 파싱되지 않는다.

**권장 수정:**
POSIX 셸 호환성을 위해 `${VAR}` 문법도 지원.

---

#### Issue #8: `KSWindowStateStore.save()` — `try?` 무성 오류 삼킴

**파일:** `Sources/KalsaeCore/PAL/KSWindowStateStore.swift` (lines 89-112)

**설명:**
```swift
guard let data = try? JSONEncoder().encode(dict) else { return false }
```

`JSONEncoder().encode()` 실패 원인(예: 순환 참조, non-string key)이 완전히 무시된다.

**영향:**
디버깅이 어려워진다.

**권장 수정:**
디버그 빌드에서 최소한 assertion이나 로그를 남기는 것이 좋다.

---

### 🔵 개선 제안 (Enhancement)

#### Issue #9: `KSIPCBridgeCore` — `_sharedEncoder`의 `@MainActor` 의존성

**파일:** `Sources/KalsaeCore/IPC/KSIPCBridgeCore.swift`

**설명:**
`_sharedEncoder`가 `static let`이지만 `@MainActor` 타입 내에 있어 접근이 `MainActor`로 제한된다. 이는 의도된 설계이지만, 만약 백그라운드에서 `encodeForJS()`가 호출되면 컴파일 오류가 발생한다.

**권장 수정:**
명시적으로 `@MainActor`임을 문서화하거나, `nonisolated`한 별도 인코더를 준비.

---

#### Issue #10: `KSBuiltinCommands.register()` — `registerQuery` 중복

**파일:** `Sources/KalsaeCore/IPC/KSBuiltinCommands.swift`

**설명:**
`registerQuery`는 `register`와 구현이 완전히 동일하다(의미론적 별칭).

**권장 수정:**
`typealias`나 `@available(*, deprecated, renamed:)`로 대체하거나 제거.

---

#### Issue #11: `KSPlatform` extension — 한글 주석 오타

**파일:** `Sources/KalsaeCore/PAL/KSPlatform.swift` (lines 69-82)

**설명:**
```swift
/// 기본값: 플랫폼이 솔 백엔드를 아직 노출하지 않는다.
public var shell: (any KSShellBackend)? { nil }
/// 기본값: 플랫폼이 자동 시작 백엔드를 노옶하지 않는다.
public var autostart: (any KSAutostartBackend)? { nil }
/// 기본값: 플랫폼이 딥 링크 백엔드를 노옶하지 않는다.
public var deepLink: (any KSDeepLinkBackend)? { nil }
```

- "솔" → "셸"
- "노옶" → "노출" (2회)

---

#### Issue #12: `KSWindowBackend.swift` — 한글 주석 오타

**파일:** `Sources/KalsaeCore/PAL/KSWindowBackend.swift`

| 위치 | 오타 | 수정 |
|------|------|------|
| line 1 | "윈돈우" | "윈도우" |
| line 27 | "철헌하고" | "구현하고" |
| line 29 | "좌은 결합" | "느슨한 결합" |
| line 118 | "캡첸한다" | "캡처한다" |
| line 25 | "윈돈우" | "윈도우" |
| line 57 | "윈돈우" | "윈도우" |
| line 60 | "윈돈우" | "윈도우" |
| line 64 | "윈돈우" | "윈도우" |
| line 67 | "윈돈우" | "윈도우" |
| line 71 | "윈돈우" | "윈도우" |
| line 77 | "윈돈우" | "윈도우" |
| line 86 | "윈돈우" | "윈도우" |
| line 99 | "윈돈우" | "윈도우" |
| line 112 | "윈돈우" | "윈도우" |
| line 117 | "윈돈우" | "윈도우" |
| line 129 | "윈돈우" | "윈도우" |
| line 144 | "윈돈우" | "윈도우" |
| line 149 | "윈돈우" | "윈도우" |

---

## 5. 종합 평가 (Summary)

### 5.1 등급: A (우수)

KalsaeCore 모듈은 전반적으로 **매우 높은 코드 품질**을 보여준다:

- **Typed throws**를 프로젝트 전체에 일관되게 적용한 점은 Swift 6.0 모범 사례를 잘 따르고 있다.
- **보안 중심 설계** (allowlist/denylist, rate limiting, 경로 검증, CSP)가 체계적으로 구현되어 있다.
- **동시성 모델**이 명확하고(`@MainActor`, `actor`, `TaskLocal`), 플랫폼별 차이를 추상화한 `hop` 패턴이 우아하다.
- **메모리/성능 최적화** (LRU 캐시, 수동 JSON 조립, 인코더 재사용)가 적절히 적용되었다.

### 5.2 우선순위별 권장 조치

| 우선순위 | Issue | 심각도 | 권장 조치 |
|----------|-------|--------|-----------|
| P0 | #1 `encodeForJS()` 수동 JSON 조립 | 🔴 Critical | 단위 테스트 추가 또는 정규 경로 리팩토링 |
| P1 | #4 `Task.detached`의 `weak self` | 🟡 Warning | `strong self` 또는 로깅 추가 |
| P2 | #5 `MainActor.run` 클로저 예외 | 🔵 Enhancement | 현 구현 유지 (AGENTS §4 준수) |
| P3 | #11, #12 한글 주석 오타 | 🔵 Enhancement | 일괄 수정 |
| P4 | #10 `registerQuery` 중복 | 🔵 Enhancement | 제거 또는 명확화 |
| P5 | #6 `NSRegularExpression` 캐싱 | 🟡 Warning | 캐싱 계층 도입 |
| P6 | #7 `${VAR}` 문법 지원 | 🟡 Warning | POSIX 호환성 개선 |
| P7 | #8 `try?` 오류 삼킴 | 🟡 Warning | 디버그 로깅 추가 |
| P8 | #2 부동소수점 정밀도 | 🔵 Enhancement | 실효 영향 미미, 백로그 관리 |
| P9 | #3 `@unchecked Sendable` | 🔵 Enhancement | 플랫폼 최소 버전 이슈로 백로그 |
| P10 | #9 `_sharedEncoder` 문서화 | 🔵 Enhancement | 명시적 문서화 |

---

## 6. 참고 (References)

- `AGENTS.md` — 프로젝트 코딩 컨벤션 및 Swift 6.0 규칙
- `SECURITY.md` — 보안 모델 문서
- `RFC-002-security-audit.md` — 이전 보안 감사 결과
- Swift 6.0: [Typed Throws](https://github.com/apple/swift-evolution/blob/main/proposals/0413-typed-throws.md)
- Swift 6.0: [Region-based Isolation](https://github.com/apple/swift-evolution/blob/main/proposals/0414-region-based-isolation.md)
