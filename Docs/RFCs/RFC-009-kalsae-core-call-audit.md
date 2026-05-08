# RFC-009 — Kalsae(Public) → KalsaeCore 호출 감사 (Audit)

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-09 |
| 영향 범위 | `Sources/Kalsae/` (KSApp, KSApp+Boot, KSApp+UI, KSApp+Plugins) |
| 관련 | `KalsaeCore` (KSCommandRegistry, KSIPCBridgeCore, KSAssetCache, KSConfigLoader, KSWindowEmitHub) |

---

## 1. 동기 (Motivation)

Kalsae(Public) 모듈은 `Sources/Kalsae/`에 위치하며, `KalsaeCore`의 타입들을 호출해 애플리케이션을 부팅(`boot`)하고, IPC를 디스패치하며, 플랫폼 백엔드를 초기화한다. 이 과정에서 메모리 누수, 타입 안전성 문제, 리소스 중복, 클로저 누락 등이 발견되었다.

본 RFC는 Kalsae(Public) → KalsaeCore 호출 과정에서 발견된 문제들을 체계적으로 정리하고 수정 방안을 제시한다.

---

## 2. 발견된 문제 목록

### 2.1 [심각] `KSApp.init`의 `deepLinkBackend` 타입 캐스팅 문제

**파일:** `Sources/Kalsae/KSApp.swift` (79-91행)

```swift
private init(
    config: KSConfig,
    registry: KSCommandRegistry,
    platform: any KSPlatform,
    host: AnyPlatformHost,
    secondaryHosts: [AnyPlatformHost] = [],
    deepLinkBackend: (Any)? = nil  // ← Any? 타입
) {
    self.config = config
    self.registry = registry
    self.platform = platform
    self.deepLinkBackend = deepLinkBackend as? any KSDeepLinkBackend  // ← as? 캐스팅
```

`deepLinkBackend` 파라미터가 `(Any)?`로 선언되어 있고, init 내부에서 `as? any KSDeepLinkBackend`로 캐스팅하고 있다. `boot()` 메서드에서는 `builtDeepLinkBackend`가 `(any KSDeepLinkBackend)?` 타입으로 전달되는데, 이 값이 `Any`로 박싱되었다가 다시 `as?`로 언박싱된다.

**문제점:** Swift에서 `any KSDeepLinkBackend` 값을 `Any`로 전달할 때 박싱이 발생하고, 다시 `as? any KSDeepLinkBackend`로 캐스팅할 때 런타임에 타입 정보가 유실될 가능성이 있다. 특히 `KSDeepLinkBackend`가 프로토콜(`protocol`)이므로, `Any`를 거치면 구체적 타입 정보가 사라져 `as?` 캐스팅이 실패할 수 있다.

**영향:** 딥링크 기능이 조용히 비활성화된다 (`deepLinkBackend`가 `nil`이 됨). `dispatchDeepLinkURLs`가 호출되어도 아무 동작도 하지 않게 된다.

**수정 방안:** `deepLinkBackend` 파라미터를 `(any KSDeepLinkBackend)?`로 직접 선언하고 `as?` 캐스팅을 제거한다.

```swift
// Before
deepLinkBackend: (Any)? = nil
// ...
self.deepLinkBackend = deepLinkBackend as? any KSDeepLinkBackend

// After
deepLinkBackend: (any KSDeepLinkBackend)? = nil
// ...
self.deepLinkBackend = deepLinkBackend
```

---

### 2.2 [중간] `KSApp+UI.swift` — 플랫폼 미구현 시 completion 클로저 누락

**파일:** `Sources/Kalsae/KSApp+UI.swift` (21-36행)

```swift
nonisolated public func showMessage(
    _ options: KSMessageOptions,
    completion: @MainActor @Sendable @escaping (KSMessageResult) -> Void = { _ in }
) {
    #if os(Windows)
        postJob {
            let result = KSWindowsDialogBackend.messageOnUI(options)
            completion(result)
        }
    #else
        KSLog.logger("kalsae.app").info(
            "showMessage is not implemented on this platform yet")
        _ = options
        _ = completion  // ← completion 클로저가 버려짐
    #endif
}
```

`showMessage`와 `openFile`에서 플랫폼이 구현되지 않은 경우 `completion` 클로저를 호출하지 않고 버린다. `openFile`은 `Task { @MainActor in completion([]) }`로 빈 결과를 전달하지만, `showMessage`는 `completion`을 완전히 무시한다.

**문제점:** 호출자가 `completion` 클로저 내부에서 중요한 리소스를 캡처했거나, semaphore를 해제하는 로직이 있다면 영구적 블로킹/리소스 누수가 발생할 수 있다.

**영향:** 비-Windows 플랫폼에서 `showMessage` 호출 시 completion 클로저가 영원히 호출되지 않아, 호출자가 대기 상태에 빠질 수 있다.

**수정 방안:** `showMessage`의 `#else` 분기에서도 `Task { @MainActor in completion(.cancel) }` 또는 유사한 폴백을 추가한다.

```swift
// Before (#else 분기)
_ = options
_ = completion

// After
Task { @MainActor in
    completion(KSMessageResult(button: .cancel, checkboxChecked: false))
}
```

---

### 2.3 [중간] `KSApp.boot` — `secondaryHosts`의 `KSAssetCache` 중복 생성

**파일:** `Sources/Kalsae/KSApp.swift` (336-337행)

```swift
let secAssetResolver = KSAssetResolver(root: secRoot, cache: KSAssetCache())
```

보조 윈도우마다 별도의 `KSAssetCache` 인스턴스를 생성하고 있다. 기본 윈도우도 별도의 캐시를 가진다. 동일한 `resourceRoot`를 공유하는 경우에도 캐시가 중복되어 메모리 사용량이 불필요하게 증가한다.

**문제점:** N개의 윈도우가 동일한 자산 디렉터리를 공유할 때, 동일한 파일이 N번 캐시되어 최대 `N × 4MB`의 중복 메모리가 발생할 수 있다. 또한 각 캐시가 독립적으로 동작하므로, 한 윈도우가 이미 캐시한 자산을 다른 윈도우가 다시 디스크에서 읽게 된다.

**영향:** 멀티 윈도우 환경에서 메모리 사용량 증가 및 디스크 I/O 중복.

**수정 방안:** `KSAssetCache`를 공유 싱글톤으로 만들거나, `resourceRoot`가 같으면 동일 캐시 인스턴스를 재사용한다.

```swift
// Before
let resolver = KSAssetResolver(root: servedRoot, cache: KSAssetCache())
// ...
let secAssetResolver = KSAssetResolver(root: secRoot, cache: KSAssetCache())

// After — resourceRoot 기준 캐시 공유
private static var sharedCaches: [String: KSAssetCache] = [:]
private static func cache(for root: URL) -> KSAssetCache {
    let key = root.standardizedFileURL.path
    if let existing = sharedCaches[key] { return existing }
    let cache = KSAssetCache()
    sharedCaches[key] = cache
    return cache
}
```

---

### 2.4 [낮음] `KSApp+Plugins.swift` — `_plugins` computed property의 불필요한 간접 참조

**파일:** `Sources/Kalsae/KSApp+Plugins.swift` (67-71행)

```swift
extension KSApp {
    var _plugins: [any KSPlugin] {
        get { _pluginsStorage }
        set { _pluginsStorage = newValue }
    }
}
```

`_plugins`는 `_pluginsStorage`를 읽고 쓰는 computed property다. `install()` 메서드에서 `_plugins.append(contentsOf: plugins)`를 호출하는데, 이는 `_pluginsStorage.append(contentsOf: plugins)`와 동일하다. computed property가 단순 getter/setter로만 동작하므로 불필요한 간접 참조 계층이다.

**문제점:** 기능적 결함은 아니지만, 코드 복잡성만 증가시킨다. `_pluginsStorage`를 직접 사용해도 동일하다.

**영향:** 없음 (코드 스타일 문제).

**수정 방안:** `_plugins` computed property를 제거하고 `_pluginsStorage`를 직접 사용한다.

```swift
// Before
var _plugins: [any KSPlugin] {
    get { _pluginsStorage }
    set { _pluginsStorage = newValue }
}
// ...
_plugins.append(contentsOf: plugins)

// After
_pluginsStorage.append(contentsOf: plugins)
```

---

### 2.5 [낮음] `KSApp.boot` — `config`의 `var` 재할당과 릴리스 빌드 devtools 강제 off

**파일:** `Sources/Kalsae/KSApp.swift` (159-162행)

```swift
var config = config
#if !DEBUG
    config.security.devtools = false
#endif
```

`config` 파라미터가 `let`이 아닌 `var`로 받아지고, 릴리스 빌드에서 `devtools`를 강제로 끈다. 이는 의도된 동작이지만, `config`가 `KSConfig` 구조체이므로 `var config = config`는 전체 구조체의 복사를 발생시킨다.

**문제점:** `KSConfig`는 여러 옵셔널 필드(`tray`, `menu`, `notifications`, `autostart`, `deepLink`)를 포함하므로, 부팅 시 불필요한 메모리 복사가 발생한다. 다만 부팅 1회만 발생하므로 성능 영향은 미미하다.

**영향:** 무시할 수 있는 수준의 부팅 시간 증가.

**수정 방안:** `inout` 파라미터를 사용하거나, 복사 후 변경이 아닌 조건부 상수로 처리한다. (선택적 개선)

---

### 2.6 [낮음] `KSApp+Helpers.swift` — `isDevServerReachable`의 `nonisolated(unsafe)` 사용

**파일:** `Sources/Kalsae/KSApp+Helpers.swift` (94행)

```swift
nonisolated(unsafe) var ok = false
```

`isDevServerReachable` 함수는 `DispatchSemaphore`를 사용해 동기적으로 dev 서버 응답을 확인한다. `nonisolated(unsafe)`는 URLSession 콜백 클로저가 `@Sendable`이 아니기 때문에 필요한 조치다.

**문제점:** `nonisolated(unsafe)`는 Swift 6의 동시성 안전성을 우회한다. 현재는 단일 스레드(`DispatchSemaphore`로 동기화)에서만 접근되므로 안전하지만, 향후 리팩터링 시 데이터 경합이 발생할 수 있다.

**영향:** 현재는 안전하나, 유지보수 위험.

**수정 방안:** `Actor`나 `@Sendable` 클로저 패턴으로 대체하거나, `Atomic` 래퍼를 도입한다. (선택적 개선)

---

## 3. 문제 매트릭스

| # | 문제 | 파일 | 심각도 | 수정 난이도 |
|---|------|------|--------|------------|
| **2.1** | **`deepLinkBackend` `Any` 캐스팅 → 딥링크 무력화** | `KSApp.swift` | **높음** | **낮음** |
| 2.2 | `showMessage` completion 클로저 누락 | `KSApp+UI.swift` | 중간 | 낮음 |
| 2.3 | `secondaryHosts` `KSAssetCache` 중복 생성 | `KSApp.swift` | 중간 | 중간 |
| 2.4 | `_plugins` 불필요한 computed property | `KSApp+Plugins.swift` | 낮음 | 낮음 |
| 2.5 | `config` 구조체 불필요한 복사 | `KSApp.swift` | 낮음 | 낮음 |
| 2.6 | `nonisolated(unsafe)` 사용 | `KSApp+Helpers.swift` | 낮음 | 중간 |

---

## 4. 수정 계획

### Phase 1: 긴급 수정 (높음 심각도)

#### 4.1 `deepLinkBackend` 타입 캐스팅 수정 (#2.1)

**파일:** `Sources/Kalsae/KSApp.swift`

`KSApp.init`의 `deepLinkBackend` 파라미터 타입을 `(Any)?`에서 `(any KSDeepLinkBackend)?`로 변경하고, `as?` 캐스팅을 제거한다.

```swift
// 변경 전
private init(
    ...
    deepLinkBackend: (Any)? = nil
) {
    ...
    self.deepLinkBackend = deepLinkBackend as? any KSDeepLinkBackend
}

// 변경 후
private init(
    ...
    deepLinkBackend: (any KSDeepLinkBackend)? = nil
) {
    ...
    self.deepLinkBackend = deepLinkBackend
}
```

---

### Phase 2: 중간 심각도 수정

#### 4.2 `showMessage` completion 폴백 추가 (#2.2)

**파일:** `Sources/Kalsae/KSApp+UI.swift`

`showMessage`의 `#else` 분기에서 completion 클로저를 호출하도록 수정한다.

```swift
// 변경 전
#else
    KSLog.logger("kalsae.app").info(
        "showMessage is not implemented on this platform yet")
    _ = options
    _ = completion
#endif

// 변경 후
#else
    KSLog.logger("kalsae.app").info(
        "showMessage is not implemented on this platform yet")
    _ = options
    Task { @MainActor in
        completion(KSMessageResult(button: .cancel, checkboxChecked: false))
    }
#endif
```

#### 4.3 `KSAssetCache` 공유 (#2.3)

**파일:** `Sources/Kalsae/KSApp.swift`

`resourceRoot` 기준으로 `KSAssetCache`를 공유하도록 수정한다. `KSApp`에 정적 캐시 저장소를 추가하거나, `KSAssetCache` 자체에 팩토리 메서드를 추가한다.

```swift
// KSApp에 정적 캐시 저장소 추가
extension KSApp {
    private static var assetCaches: [String: KSAssetCache] = [:]
    private static func sharedCache(for root: URL) -> KSAssetCache {
        let key = root.standardizedFileURL.path
        if let cache = assetCaches[key] { return cache }
        let cache = KSAssetCache()
        assetCaches[key] = cache
        return cache
    }
}
```

---

### Phase 3: 낮음 심각도 (선택적 개선)

#### 4.4 `_plugins` computed property 제거 (#2.4)

**파일:** `Sources/Kalsae/KSApp+Plugins.swift`

`_plugins` computed property를 제거하고 `_pluginsStorage`를 직접 사용한다.

#### 4.5 `config` 복사 최적화 (#2.5)

**파일:** `Sources/Kalsae/KSApp.swift`

`var config = config` 대신 조건부 상수로 처리하거나, `boot(config:windowLabel:...)`의 시그니처를 `inout`으로 변경하는 것을 검토한다.

#### 4.6 `nonisolated(unsafe)` 대체 (#2.6)

**파일:** `Sources/Kalsae/KSApp+Helpers.swift`

`isDevServerReachable`의 `nonisolated(unsafe)`를 `Actor` 기반 동기화 또는 `@Sendable` 클로저 패턴으로 대체한다.

---

## 5. FAQ

### Q: `deepLinkBackend`를 `Any?`로 선언한 이유가 있나요?

초기 설계에서 `Any?`를 사용한 정확한 이유는 파악되지 않았습니다. `boot()` 메서드에서 `builtDeepLinkBackend`는 `(any KSDeepLinkBackend)?` 타입으로 생성되므로, `Any?`를 거칠 필요가 없습니다. 단순한 코딩 실수로 추정됩니다.

### Q: `showMessage`의 completion 클로저가 호출되지 않으면 어떤 문제가 발생하나요?

호출자가 `completion` 내부에서 `DispatchSemaphore.signal()`이나 `Continuation.resume()`을 호출하는 경우, 해당 호출이 영원히 대기 상태에 빠집니다. 또한 클로저가 캡처한 리소스(파일 핸들, 네트워크 연결 등)가 정리되지 않아 누수가 발생할 수 있습니다.

### Q: `KSAssetCache`를 공유하면 스레드 안전성에 문제가 없나요?

`KSAssetCache`는 내부적으로 `NSLock`으로 동기화되고 `@unchecked Sendable`로 선언되어 있으므로, 여러 윈도우에서 동시에 접근해도 안전합니다. 다만 `KSAssetResolver`는 값 타입이므로 각 윈도우가 별도의 `KSAssetResolver` 인스턴스를 가지되, 동일한 `KSAssetCache` 참조를 공유하는 방식이 안전합니다.

---

## 6. 변경 이력

| 날짜 | 변경 내용 |
|------|----------|
| 2026-05-09 | 초안 작성 |
