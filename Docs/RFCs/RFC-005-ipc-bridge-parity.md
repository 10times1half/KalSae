# RFC-005 — IPC 브리지 크로스 플랫폼 동등성 개선

| 항목 | 내용 |
|------|------|
| 상태 | 초안 (Draft) |
| 날짜 | 2026-05-09 |
| 영향 범위 | KalsaeCore IPC, 전 플랫폼 런타임 JS, KSWindowEmitHub |
| 관련 | KSIPCBridgeCore, KSRuntimeJS (Win/Mac/Linux/iOS/Android) |

---

## 1. 동기(Motivation)

Swift ↔ 프론트엔드 IPC 브리지를 플랫폼별로 검토한 결과, Windows 런타임 JS를
기준으로 macOS/Linux/iOS/Android에서 **API 계약 불일치**(버그 3건)와
**기능 격차**(개선 5건)를 발견했다.

프론트엔드 개발자가 플랫폼에 따라 다른 에러 처리 코드를 작성해야 하거나,
특정 플랫폼에서만 편의 API를 사용할 수 있는 상태는 "한 번 작성하면 어디서나
실행" 원칙에 위배된다. 또한 `KSWindowEmitHub`의 브로드캐스트 버그는 멀티
윈도우 환경에서 이벤트 전파를 깨뜨린다.

이 RFC는 Windows 런타임을 참조 모델로 삼아 전 플랫폼의 IPC 레이어를
동등 수준으로 끌어올리는 상세 구현 계획이다.

---

## 2. 요약

| # | 유형 | 심각도 | 영역 | 요약 |
|---|------|--------|------|------|
| 1 | 버그 | **높음** | 런타임 JS | macOS/Linux/iOS/Android에서 invoke 에러가 `Error` 인스턴스가 아님 |
| 2 | 버그 | 중간 | iOS/Android PAL | 창 close 시 `KSWindowEmitHub` 등록 해제 누락 |
| 3 | 버그 | 중간 | KSWindowEmitHub | 브로드캐스트 중 첫 에러에서 나머지 창 전파 중단 |
| 4 | 개선 | 중간 | 런타임 JS | macOS/Linux/iOS 편의 API 누락 (`window.*`, `shell.*` 등) |
| 5 | 개선 | 중간 | 런타임 JS | Promise `pending` Map에 타임아웃/정리 메커니즘 없음 |
| 6 | 개선 | 낮음 | PAL + 런타임 JS | `__ks.window.startDrag` 플랫폼 공통 등록 누락 |
| 7 | 개선 | 낮음 | KSCommandRegistry | Rate limiter가 단일 글로벌 버킷 (내장 명령도 제한) |
| 8 | 개선 | 낮음 | WKWebViewHost | `postJSON`에서 U+2028/U+2029 미이스케이핑 |

---

## 3. Phase 구조 및 의존성

```
Phase 1 (버그 수정 — 즉시 착수, 1A/1B/1C 병렬)
  ├─ 1A: KalsaeError 클래스 통일 (#1)
  ├─ 1B: EmitHub 해제 누락 수정 (#2)
  └─ 1C: 브로드캐스트 중단 수정 (#3)

Phase 2 (개선 — Phase 1 완료 후, 2A/2B/2C 병렬)
  ├─ 2A: 편의 JS API 통일 (#4)       ← depends on 1A
  ├─ 2B: Promise 타임아웃 (#5)        ← depends on 1A
  └─ 2C: startDrag 공통 등록 (#6)     ← depends on 2A (드래그 JS)

Phase 3 (하위 우선순위 — Phase 2 완료 후)
  ├─ 3A: Rate limiter 세분화 (#7)
  └─ 3B: postJSON U+2028 처리 (#8)
```

---

## 4. 상세 구현

### 4.1 Phase 1A — `KalsaeError` 클래스 통일

#### 현황

**Windows** (`Sources/KalsaePlatformWindows/WebView2/KSRuntimeJS.swift` L20–55):
```javascript
class KalsaeError extends Error {
  constructor(payload) {
    const p = (payload && typeof payload === 'object') ? payload : {};
    super(p.message || String(payload || 'Kalsae error'));
    this.name = 'KalsaeError';
    this.code = p.code || 'internal';
    this.data = (p.data === undefined) ? null : p.data;
  }
}
window.KalsaeError = KalsaeError;
// ...
if (msg.isError) p.reject(new KalsaeError(msg.payload));
```

**macOS** (`Sources/KalsaePlatformMac/WebKit/KSRuntimeJS.swift` L31):
```javascript
if (msg.isError) p.reject(msg.payload);  // ← 원시 객체로 reject
```

**Linux** (`Sources/KalsaePlatformLinux/Gtk/GtkWebViewHost.swift` KSRuntimeJS enum):
```javascript
if (msg.isError) p.reject(msg.payload);  // ← 동일
```

**iOS** (`Sources/KalsaePlatformIOS/WebKit/KSiOSWebViewHost.swift` KSiOSRuntimeJS):
```javascript
if (msg.isError) p.reject(msg.payload);  // ← 동일
```

#### 문제

1. `catch(e)` 에서 `e instanceof Error === false` → `e.stack` 없음, 디버깅 어려움
2. `instanceof KalsaeError` 타입 가드 불가 (Windows에서만 동작)
3. 프론트엔드 개발자가 플랫폼별 다른 에러 처리 코드를 작성해야 함

#### 변경 대상 파일

| 파일 | 변경 |
|------|------|
| `Sources/KalsaePlatformMac/WebKit/KSRuntimeJS.swift` | IIFE 앞부분에 `KalsaeError` 클래스 추가 + `p.reject` 줄 변경 |
| `Sources/KalsaePlatformLinux/Gtk/GtkWebViewHost.swift` (KSRuntimeJS enum 내부) | 동일 |
| `Sources/KalsaePlatformIOS/WebKit/KSiOSWebViewHost.swift` (KSiOSRuntimeJS enum 내부) | 동일 |
| `Sources/KalsaePlatformAndroid/WebView/KSAndroidWebViewHost.swift` | 동일 (Android 런타임 JS 확인 후 적용) |

#### 변경 내역

##### 1) `KalsaeError` 클래스 정의 추가 (IIFE 시작 직후, `pending` 선언 전)

```javascript
// 모든 플랫폼에 다음을 추가 (Windows와 동일)
class KalsaeError extends Error {
  constructor(payload) {
    const p = (payload && typeof payload === 'object') ? payload : {};
    super(p.message || String(payload || 'Kalsae error'));
    this.name = 'KalsaeError';
    this.code = p.code || 'internal';
    this.data = (p.data === undefined) ? null : p.data;
  }
}
window.KalsaeError = KalsaeError;
```

##### 2) `handleInbound` 응답 처리 변경

```javascript
// 변경 전:
if (msg.isError) p.reject(msg.payload);

// 변경 후:
if (msg.isError) p.reject(new KalsaeError(msg.payload));
```

#### 하위 호환성

- `window.KalsaeError`는 이전에 비-Windows 플랫폼에서 정의되지 않았으므로 추가해도
  기존 코드를 깨지 않음.
- `catch(e) { console.log(e.code) }` 패턴은 프로퍼티가 동일하므로 계속 동작.
- **새로운 이점**: `e instanceof Error === true`, `e.stack` 포함,
  `instanceof KalsaeError` 타입 가드 가능.

---

### 4.2 Phase 1B — iOS/Android `KSWindowEmitHub` 해제 누락 수정

#### 현황

| 플랫폼 | close 시 `KSWindowEmitHub.shared.unregister` 호출 여부 |
|--------|-------------------------------------------------------|
| Windows | ✅ `Sources/KalsaePlatformWindows/Win32/Win32Window+WndProc.swift` L219 |
| macOS | ✅ `Sources/KalsaePlatformMac/PAL/KSMacWindowBackend.swift` L79 |
| Linux | ✅ `Sources/KalsaePlatformLinux/KSLinuxPlatform.swift` L173 |
| **iOS** | ❌ `KSiOSHandleRegistry.unregister(handle)` 만 호출 |
| **Android** | ❌ `Registry.close(handle)` 만 호출 |

#### 문제

- 창 닫힌 후에도 `KSWindowEmitHub.sinks`에 해당 레이블이 잔존
- 브로드캐스트 시 dead `weak self` 참조의 sink에 호출 시도
- 메모리 누수 + 잠재적 에러 전파

#### 변경 내역

##### iOS: `KSiOSWindowBackend.close()`

```swift
// Sources/KalsaePlatformIOS/PAL/KSiOSWindowBackend.swift

// 변경 전:
public func close(_ handle: KSWindowHandle) async throws(KSError) {
    await MainActor.run {
        KSiOSHandleRegistry.shared.unregister(handle)
    }
}

// 변경 후:
public func close(_ handle: KSWindowHandle) async throws(KSError) {
    await MainActor.run {
        KSiOSHandleRegistry.shared.unregister(handle)
        KSWindowEmitHub.shared.unregister(label: handle.label)
    }
}
```

##### Android: `KSAndroidWindowBackend.close()`

```swift
// Sources/KalsaePlatformAndroid/KSAndroidPlatform.swift

// 변경 전:
public func close(_ handle: KSWindowHandle) async throws(KSError) {
    await registry.close(handle)
}

// 변경 후:
public func close(_ handle: KSWindowHandle) async throws(KSError) {
    await registry.close(handle)
    await MainActor.run {
        KSWindowEmitHub.shared.unregister(label: handle.label)
    }
}
```

> **import 확인:** 두 파일 모두 `public import KalsaeCore`가 이미 있으므로
> `KSWindowEmitHub` 접근 가능.

---

### 4.3 Phase 1C — `KSWindowEmitHub.emit` 브로드캐스트 중단 수정

#### 현황

`Sources/KalsaeCore/IPC/KSWindowEmitHub.swift` L43–46:
```swift
} else {
    for sink in sinks.values {
        try sink(event, payload)  // 하나라도 throw → 루프 중단
    }
}
```

#### 문제

- 창 A의 sink가 에러 throw → 창 B, C는 이벤트를 미수신
- 멀티 윈도우 앱에서 하나의 webview 상태가 브로드캐스트 전체를 깨뜨림

#### 변경 내역

```swift
// Sources/KalsaeCore/IPC/KSWindowEmitHub.swift

// 변경 전:
    public func emit(
        event: String,
        payload: any Encodable,
        to label: String?
    ) throws(KSError) {
        if let label {
            guard let sink = sinks[label] else {
                throw KSError(code: .invalidArgument, message: "No window registered for label '\(label)'")
            }
            try sink(event, payload)
        } else {
            for sink in sinks.values {
                try sink(event, payload)
            }
        }
    }

// 변경 후:
    public func emit(
        event: String,
        payload: any Encodable,
        to label: String?
    ) throws(KSError) {
        if let label {
            guard let sink = sinks[label] else {
                throw KSError(code: .invalidArgument, message: "No window registered for label '\(label)'")
            }
            try sink(event, payload)
        } else {
            var firstError: KSError?
            for sink in sinks.values {
                do {
                    try sink(event, payload)
                } catch let e {
                    if firstError == nil { firstError = e }
                }
            }
            if let firstError { throw firstError }
        }
    }
```

#### 동작 변경

| 시나리오 | 변경 전 | 변경 후 |
|---------|--------|--------|
| 창 3개 중 2번째 실패 | 3번째 이벤트 미수신 | 3번째 정상 수신, 첫 에러 throw |
| 모든 창 성공 | 정상 | 정상 (동일) |
| 단일 창 타겟 | 동일 | 동일 (변경 없음) |

---

### 4.4 Phase 2A — 편의 JS API 플랫폼 통일

#### 현황

**Windows** 런타임은 ~120줄의 편의 메서드 레이어를 제공:
```javascript
window.__KS_ = Object.freeze({
  invoke, listen, emit,
  window: Win,       // minimize, maximize, setSize, ... 30+ methods
  shell: Shell,      // openExternal, showItemInFolder, moveToTrash
  dialog: Dialog,    // openFile, saveFile, selectFolder, message
  clipboard: Clipboard,  // readText, writeText, clear, hasFormat
  app: App,          // quit, environment, hide, show
  events: Events,    // on, off, once, offAll, emit
  log: Log,          // trace, debug, info, warn, error
});
```

**macOS/Linux/iOS**는:
```javascript
window.__KS_ = KB;  // invoke/listen/emit만 노출
```

#### 변경 대상 파일

| 파일 | 변경 |
|------|------|
| `Sources/KalsaePlatformMac/WebKit/KSRuntimeJS.swift` | 편의 레이어 추가 |
| `Sources/KalsaePlatformLinux/Gtk/GtkWebViewHost.swift` (KSRuntimeJS) | 동일 |
| `Sources/KalsaePlatformIOS/WebKit/KSiOSWebViewHost.swift` (KSiOSRuntimeJS) | 동일 |
| `Sources/KalsaePlatformAndroid/WebView/KSAndroidWebViewHost.swift` | 동일 |

#### 추가할 코드 (KB 객체 정의 직후, `window.__KS_ = KB` 줄을 교체)

```javascript
              function call(name, args) { return KB.invoke(name, args); }

              // ---- 윈도우 ----
              const Win = Object.freeze({
                minimize:         () => call('__ks.window.minimize'),
                maximize:         () => call('__ks.window.maximize'),
                restore:          () => call('__ks.window.restore'),
                toggleMaximize:   () => call('__ks.window.toggleMaximize'),
                isMinimized:      () => call('__ks.window.isMinimized'),
                isMaximized:      () => call('__ks.window.isMaximized'),
                isFullscreen:     () => call('__ks.window.isFullscreen'),
                isNormal:         () => call('__ks.window.isNormal'),
                setFullscreen:    (enabled, window) => call('__ks.window.setFullscreen', { enabled: !!enabled, window: window || null }),
                setAlwaysOnTop:   (enabled, window) => call('__ks.window.setAlwaysOnTop', { enabled: !!enabled, window: window || null }),
                center:           () => call('__ks.window.center'),
                setPosition:      (x, y, window) => call('__ks.window.setPosition', { x: x|0, y: y|0, window: window || null }),
                getPosition:      () => call('__ks.window.getPosition'),
                getSize:          () => call('__ks.window.getSize'),
                setSize:          (width, height, window) => call('__ks.window.setSize', { width: width|0, height: height|0, window: window || null }),
                setMinSize:       (width, height, window) => call('__ks.window.setMinSize', { width: width|0, height: height|0, window: window || null }),
                setMaxSize:       (width, height, window) => call('__ks.window.setMaxSize', { width: width|0, height: height|0, window: window || null }),
                setTitle:         (title, window) => call('__ks.window.setTitle', { title: String(title), window: window || null }),
                show:             () => call('__ks.window.show'),
                hide:             () => call('__ks.window.hide'),
                focus:            () => call('__ks.window.focus'),
                close:            () => call('__ks.window.close'),
                reload:           () => call('__ks.window.reload'),
                setTheme:         (theme, window) => call('__ks.window.setTheme', { theme: String(theme || 'system'), window: window || null }),
                setBackgroundColor: (r, g, b, a, window) => call('__ks.window.setBackgroundColor', { r: (r|0)&0xFF, g: (g|0)&0xFF, b: (b|0)&0xFF, a: a === undefined ? 255 : (a|0)&0xFF, window: window || null }),
                setCloseInterceptor: (enabled, window) => call('__ks.window.setCloseInterceptor', { enabled: !!enabled, window: window || null }),
                setZoom:          (factor, window) => call('__ks.window.setZoom', { factor: Number(factor) || 1.0, window: window || null }),
                getZoom:          () => call('__ks.window.getZoom'),
                print:            (opts) => call('__ks.window.print', { systemDialog: !!(opts && opts.systemDialog), window: (opts && opts.window) || null }),
                capturePreview:   (opts) => call('__ks.window.capturePreview', { format: (opts && opts.format) || 'png', window: (opts && opts.window) || null }),
                displays:         () => call('__ks.window.displays'),
                currentDisplay:   (window) => call('__ks.window.currentDisplay', window ? { window } : {}),
                setTaskbarProgress: (type, value, window) => call('__ks.window.setTaskbarProgress', { progress: { type: String(type || 'none'), value: value !== undefined ? Number(value) : undefined }, window: window || null }),
                setOverlayIcon:   (iconPath, description, window) => call('__ks.window.setOverlayIcon', { iconPath: iconPath || null, description: description || null, window: window || null }),
              });

              // ---- 셸 ----
              const Shell = Object.freeze({
                openExternal:     (url) => call('__ks.shell.openExternal', { url: String(url) }),
                showItemInFolder: (path) => call('__ks.shell.showItemInFolder', { url: String(path) }),
                moveToTrash:      (path) => call('__ks.shell.moveToTrash', { url: String(path) }),
              });

              // ---- 다이얼로그 ----
              const Dialog = Object.freeze({
                openFile:     (opts) => call('__ks.dialog.openFile', opts || {}),
                saveFile:     (opts) => call('__ks.dialog.saveFile', opts || {}),
                selectFolder: (opts) => call('__ks.dialog.selectFolder', opts || {}),
                message:      (opts) => call('__ks.dialog.message', opts || {}),
              });

              // ---- 클립보드 ----
              const Clipboard = Object.freeze({
                readText:  () => call('__ks.clipboard.readText'),
                writeText: (text) => call('__ks.clipboard.writeText', { text: String(text) }),
                clear:     () => call('__ks.clipboard.clear'),
                hasFormat: (format) => call('__ks.clipboard.hasFormat', { format: String(format) }),
              });

              // ---- 앱 ----
              const App = Object.freeze({
                quit:        () => call('__ks.app.quit'),
                environment: () => call('__ks.environment'),
                hide:        () => call('__ks.window.hide'),
                show:        () => call('__ks.window.show'),
              });

              // ---- 이벤트 ----
              const Events = Object.freeze({
                on(event, cb)   { return KB.listen(event, cb); },
                off(event, cb)  {
                  const set = listeners.get(event);
                  if (set) set.delete(cb);
                },
                once(event, cb) {
                  const off = KB.listen(event, (payload) => {
                    try { off(); } finally { cb(payload); }
                  });
                  return off;
                },
                offAll(event)   {
                  if (event === undefined) listeners.clear();
                  else listeners.delete(event);
                },
                emit: KB.emit,
              });

              // ---- 로그 ----
              function logAt(level) {
                return function (...args) {
                  const text = args.map(a =>
                    (typeof a === 'string') ? a
                      : (a instanceof Error) ? (a.stack || a.message)
                      : (() => { try { return JSON.stringify(a); } catch (_) { return String(a); } })()
                  ).join(' ');
                  try { call('__ks.log', { level, message: text }).catch(() => {}); }
                  catch (_) {}
                  const fn = console[level === 'trace' ? 'debug' : (level === 'warn' ? 'warn' : (level === 'error' ? 'error' : 'log'))];
                  try { fn.apply(console, args); } catch (_) {}
                };
              }
              const Log = Object.freeze({
                trace: logAt('trace'),
                debug: logAt('debug'),
                info:  logAt('info'),
                warn:  logAt('warn'),
                error: logAt('error'),
              });

              const Root = Object.freeze({
                invoke: KB.invoke,
                listen: KB.listen,
                emit:   KB.emit,
                window: Win,
                shell:  Shell,
                dialog: Dialog,
                clipboard: Clipboard,
                app:    App,
                events: Events,
                log:    Log,
              });

              window.__KS_ = Root;
              if (!window.Kalsae) window.Kalsae = Root;
              window.__KS_receive = handleInbound;
```

#### 제외 사항

- **드래그 영역 JS** (`document.addEventListener('mousedown', ...)`): Phase 2C에서
  데스크톱 플랫폼(Windows/macOS/Linux)에만 추가. iOS/Android는 제외.
- **`nativePost`** 함수: 플랫폼별 유지 (변경 없음)

---

### 4.5 Phase 2B — Promise 타임아웃/GC

#### 현황

모든 플랫폼의 런타임 JS:
```javascript
const pending = new Map();  // id -> {resolve, reject}
```

Swift 측 핸들러가 응답을 보내지 않으면(Task 취소, crash, 무한 대기 등)
Promise가 영원히 pending 상태 → 메모리 누수 + `await` 영구 block.

#### 변경 내역

모든 플랫폼의 `KB.invoke` 메서드를 타임아웃 래핑으로 교체:

```javascript
              const INVOKE_TIMEOUT_MS = 30000;  // 30초

              const KB = Object.freeze({
                invoke(cmd, args) {
                  return new Promise((resolve, reject) => {
                    const id = String(nextId++);
                    const timer = setTimeout(() => {
                      if (pending.has(id)) {
                        pending.delete(id);
                        reject(new KalsaeError({
                          code: 'timeout',
                          message: 'invoke(\'' + cmd + '\') timed out after ' + INVOKE_TIMEOUT_MS + 'ms'
                        }));
                      }
                    }, INVOKE_TIMEOUT_MS);
                    pending.set(id, {
                      resolve(v) { clearTimeout(timer); resolve(v); },
                      reject(e) { clearTimeout(timer); reject(e); },
                    });
                    nativePost({
                      kind: 'invoke',
                      id,
                      name: cmd,
                      payload: args === undefined ? null : args,
                    });
                  });
                },
                // listen, emit은 변경 없음
                ...
              });
```

그리고 `handleInbound`의 기존 resolve/reject 호출도 래퍼를 통과하도록 변경:

```javascript
              function handleInbound(msg) {
                if (!msg || typeof msg !== 'object') return;
                switch (msg.kind) {
                  case 'response': {
                    const p = pending.get(msg.id);
                    if (!p) return;
                    pending.delete(msg.id);
                    if (msg.isError) p.reject(new KalsaeError(msg.payload));
                    else p.resolve(msg.payload);
                    break;
                  }
                  // event 핸들링 동일
                }
              }
```

> `p.resolve`/`p.reject` 호출 시 내부에서 `clearTimeout(timer)`가 자동 실행되므로
> 정상 응답 시 타이머가 정리된다.

#### 설계 결정

| 항목 | 결정 | 근거 |
|------|------|------|
| 기본 타임아웃 | 30초 | IPC 명령은 로컬 처리이므로 30초이면 충분. URLSession 기본(60초)보다 짧음 |
| Dialog 등 장시간 명령 | 향후 per-command 옵션 추가 고려 | `__ks.dialog.openFile`은 사용자 대기 → 30초 초과 가능. v1에서는 타임아웃을 경고로만 처리하고 reject하지 않는 방안도 고려했으나, 일관성을 위해 단일 정책 적용. 향후 `invoke(cmd, args, { timeout: 0 })` 무제한 옵션 추가 |
| `clearTimeout` | resolve/reject 래퍼 내부 | 타이머 누수 방지 |
| 에러 코드 | `'timeout'` | 기존 `KSError.Code`와 별개 — JS 전용 에러 (Swift로 전파되지 않음) |

#### 대안 고려

- **Swift 측 타임아웃**: `KSCommandRegistry.dispatch`에서 Task에 timeout 적용.
  → 더 견고하지만 Swift 6.0에 `withTimeout` 없음. `Task.sleep` + `withTaskGroup` 패턴으로
  구현 가능하나 복잡도 증가. 별도 RFC로 추진 가능.
- **결론**: JS 측 타임아웃(사용자 경험 보호)을 v1으로, Swift 측 취소는 향후 개선.

---

### 4.6 Phase 2C — `startDrag` 공통 등록

#### 현황

- `__ks.window.startDrag`는 `KSWindowsDemoHost`에서만 로컬 등록
  (`Sources/KalsaePlatformWindows/KSWindowsDemoHost.swift` L408)
- Windows JS 런타임만 드래그 영역 감지 코드(mousedown/dblclick) 포함
- macOS/Linux에서는 완전히 미지원
- `KSWindowBackend` 프로토콜에 `startDrag` 메서드 없음

#### 변경 내역

##### 1) `KSWindowState` 프로토콜에 `startDrag` 추가

```swift
// Sources/KalsaeCore/PAL/KSWindowBackend.swift
// KSWindowState 프로토콜에 추가:

    /// 현재 마우스 위치에서 창 드래그를 시작한다 (title bar 클릭 시뮬레이션).
    /// CSS `app-region: drag`에 의해 JS에서 호출된다.
    func startDrag(_ handle: KSWindowHandle) async throws(KSError)
```

##### 2) 기본 구현 (non-desktop 플랫폼용)

```swift
// Sources/KalsaeCore/PAL/KSWindowBackend.swift 하단
extension KSWindowState {
    public func startDrag(_ handle: KSWindowHandle) async throws(KSError) {
        // 기본: no-op. 데스크톱 플랫폼(Windows/macOS/Linux)이 재정의한다.
    }
}
```

##### 3) `KSBuiltinCommands+Window.swift`에 등록

```swift
// Sources/KalsaeCore/IPC/KSBuiltinCommands+Window.swift
// registerWindowCommands 함수 끝부분, setOverlayIcon 등록 직후에 추가:

        await register(registry, "__ks.window.startDrag") { _ throws(KSError) -> Empty in
            let h = try await resolver.resolve(window: nil)
            try await windows.startDrag(h)
            return Empty()
        }
```

##### 4) Windows PAL 구현

```swift
// Sources/KalsaePlatformWindows/PAL/KSWindowsWindowBackend.swift
public func startDrag(_ handle: KSWindowHandle) async throws(KSError) {
    await MainActor.run {
        guard let win = KSWin32HandleRegistry.shared.window(for: handle.label) else { return }
        win.startDrag()
    }
}
```

##### 5) macOS PAL 구현

```swift
// Sources/KalsaePlatformMac/PAL/KSMacWindowBackend.swift
public func startDrag(_ handle: KSWindowHandle) async throws(KSError) {
    await MainActor.run {
        guard let nsWindow = KSMacHandleRegistry.shared.nsWindow(for: handle.label) else { return }
        guard let event = NSApp.currentEvent else { return }
        nsWindow.performDrag(with: event)
    }
}
```

##### 6) Linux PAL 구현

```swift
// Sources/KalsaePlatformLinux/PAL/ (KSLinuxWindowBackend.swift 또는 해당 파일)
public func startDrag(_ handle: KSWindowHandle) async throws(KSError) {
    await MainActor.run {
        // GTK4: GdkToplevel begin_move 또는 동등 API
        // ks_gtk_host_begin_move(hostPtr) 형태로 C shim 위임
    }
}
```

##### 7) `KSWindowsDemoHost`에서 로컬 등록 제거

```swift
// Sources/KalsaePlatformWindows/KSWindowsDemoHost.swift L407–416
// 아래 블록 삭제 (KSBuiltinCommands가 이제 등록):
//     await registry.register("__ks.window.startDrag") { [weak self] _ in
//         await MainActor.run {
//             self?.window.startDrag()
//         }
//         return .success(Data("{}".utf8))
//     }
```

##### 8) 드래그 영역 감지 JS — macOS/Linux 런타임에 추가

Windows 런타임의 L238–290에 있는 드래그 영역 이벤트 리스너를 macOS/Linux에도
추가한다 (Phase 2A의 편의 코드 직후):

```javascript
              // ---- 드래그 영역 지원 ----
              function isInteractive(el) {
                if (!el || el.nodeType !== 1) return false;
                const tag = el.tagName;
                if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT'
                    || tag === 'BUTTON' || tag === 'A' || tag === 'OPTION'
                    || tag === 'VIDEO' || tag === 'AUDIO') return true;
                if (el.isContentEditable) return true;
                return false;
              }
              function regionOf(el) {
                const cs = window.getComputedStyle(el);
                const v = (cs.getPropertyValue('app-region')
                        || cs.getPropertyValue('-webkit-app-region')
                        || cs.getPropertyValue('--ks-app-region') || '').trim();
                return v;
              }
              document.addEventListener('mousedown', function (ev) {
                if (ev.button !== 0) return;
                if (ev.ctrlKey || ev.shiftKey || ev.altKey || ev.metaKey) return;
                let el = ev.target;
                while (el && el.nodeType === 1) {
                  if (isInteractive(el)) return;
                  const r = regionOf(el);
                  if (r === 'no-drag') return;
                  if (r === 'drag') {
                    ev.preventDefault();
                    try { call('__ks.window.startDrag').catch(() => {}); } catch (_) {}
                    return;
                  }
                  el = el.parentNode;
                }
              }, true);
              document.addEventListener('dblclick', function (ev) {
                if (ev.button !== 0) return;
                let el = ev.target;
                while (el && el.nodeType === 1) {
                  if (isInteractive(el)) return;
                  const r = regionOf(el);
                  if (r === 'no-drag') return;
                  if (r === 'drag') {
                    ev.preventDefault();
                    try { call('__ks.window.toggleMaximize').catch(() => {}); } catch (_) {}
                    return;
                  }
                  el = el.parentNode;
                }
              }, true);
```

> **iOS/Android**: 드래그 영역이 무의미하므로 런타임 JS에서 제외. 프로토콜
> 기본 구현(no-op)으로 충분.

---

### 4.7 Phase 3A — Rate Limiter 세분화

#### 현황

`Sources/KalsaeCore/IPC/KSCommandRegistry.swift`:
```swift
private var rateLimit: KSCommandRateLimit? = nil  // 단일 글로벌 버킷
```

모든 명령(`__ks.log`, `__ks.window.getPosition`, 사용자 `@KSCommand` 등)이
동일한 토큰 풀에서 차감. 고빈도 호출(`__ks.log` 등)이 저빈도 명령의 토큰을 소진
가능.

#### 변경 내역

##### 1) `KSCommandRateLimit` 확장

```swift
// Sources/KalsaeCore/Config/KSCommandRateLimit.swift

// 변경 전:
public struct KSCommandRateLimit: Codable, Sendable, Equatable {
    public var rate: Int
    public var burst: Int

    public init(rate: Int = 100, burst: Int = 200) {
        self.rate = max(1, rate)
        self.burst = max(1, burst)
    }
}

// 변경 후:
public struct KSCommandRateLimit: Codable, Sendable, Equatable {
    public var rate: Int
    public var burst: Int
    /// 속도 제한에서 제외할 명령 프리픽스 목록.
    /// 이 프리픽스로 시작하는 명령은 토큰을 소비하지 않는다.
    /// 기본값: `["__ks."]` (프레임워크 내장 명령 면제).
    public var exemptPrefixes: [String]

    public init(rate: Int = 100, burst: Int = 200, exemptPrefixes: [String] = ["__ks."]) {
        self.rate = max(1, rate)
        self.burst = max(1, burst)
        self.exemptPrefixes = exemptPrefixes
    }
}
```

##### 2) `KSCommandRegistry.dispatch`에서 면제 체크

```swift
// Sources/KalsaeCore/IPC/KSCommandRegistry.swift

// 변경 전:
    public func dispatch(name: String, args: Data) async -> Result<Data, KSError> {
        if !consumeToken() {
            return .failure(.rateLimited(name))
        }
        // ...
    }

// 변경 후:
    public func dispatch(name: String, args: Data) async -> Result<Data, KSError> {
        let isExempt = rateLimit.flatMap { limit in
            limit.exemptPrefixes.contains(where: { name.hasPrefix($0) })
                ? true : nil
        } ?? false
        if !isExempt && !consumeToken() {
            return .failure(.rateLimited(name))
        }
        // ...
    }
```

#### JSON 구성 예시

```json
"commandRateLimit": {
  "rate": 100,
  "burst": 200,
  "exemptPrefixes": ["__ks."]
}
```

#### 하위 호환성

- 기본값 `["__ks."]`이므로 `exemptPrefixes`를 명시하지 않아도 기존 동작 유지
- JSON에서 `exemptPrefixes` 키가 없으면 Codable 기본값이 적용됨
  → `init(from decoder:)` 커스텀 구현 또는 optional + default nil 패턴 필요:

```swift
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rate = max(1, try container.decode(Int.self, forKey: .rate))
        burst = max(1, try container.decode(Int.self, forKey: .burst))
        exemptPrefixes = (try? container.decode([String].self, forKey: .exemptPrefixes)) ?? ["__ks."]
    }
```

---

### 4.8 Phase 3B — `postJSON` U+2028/U+2029 처리

#### 현황

macOS `Sources/KalsaePlatformMac/WebKit/WKWebViewHost.swift` L141:
```swift
public func postJSON(_ json: String) throws(KSError) {
    let script = "window.__KS_receive(\(json));"
    webView.evaluateJavaScript(script) { _, err in ... }
}
```

`JSONEncoder`는 U+2028(Line Separator)/U+2029(Paragraph Separator)를 이스케이핑하지
않지만, ECMAScript에서 이 문자들은 라인 터미네이터로 취급되어 문자열 리터럴 내부에서
구문 오류를 유발할 수 있다.

> **참고:** 실제 IPC 경로(`KSIPCBridgeCore.encodeForJS` → `appendJSEscapedRaw`)는
> 이미 U+2028/U+2029를 정상 처리함. 이 이슈는 `postJSON`을 직접 사용하는 경로에만 해당.

#### 변경 내역

##### macOS

```swift
// Sources/KalsaePlatformMac/WebKit/WKWebViewHost.swift

// 변경 전:
        public func postJSON(_ json: String) throws(KSError) {
            let script = "window.__KS_receive(\(json));"
            webView.evaluateJavaScript(script) { _, err in
                if let err {
                    KSLog.logger("platform.mac.webview")
                        .warning("evaluateJavaScript failed: \(err)")
                }
            }
        }

// 변경 후:
        public func postJSON(_ json: String) throws(KSError) {
            let safe = json
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            let script = "window.__KS_receive(\(safe));"
            webView.evaluateJavaScript(script) { _, err in
                if let err {
                    KSLog.logger("platform.mac.webview")
                        .warning("evaluateJavaScript failed: \(err)")
                }
            }
        }
```

##### iOS

```swift
// Sources/KalsaePlatformIOS/WebKit/KSiOSWebViewHost.swift — postJSON 동일 변경
```

##### Linux

```swift
// Sources/KalsaePlatformLinux/Gtk/GtkWebViewHost.swift — postJSON 동일 변경
```

> **Windows**: WebView2의 `PostWebMessageAsJson`은 JSON을 메시지 이벤트 데이터로
> 전달하므로 문자열 리터럴 구문 문제가 없다. 변경 불필요.

---

## 5. 테스트 계획

테스트는 swift-testing (`@Test`, `@Suite`, `#expect`)을 사용한다.

### 5.1 `KSWindowEmitHubTests.swift` (추가 테스트)

```swift
@Suite("EmitHub 브로드캐스트")
struct KSWindowEmitHubBroadcastTests {
    @Test("하나의 sink 실패 시 나머지 sink는 정상 수신")
    func broadcastContinuesOnFailure() async throws {
        let hub = KSWindowEmitHub(_testIsolated: ())
        var received: [String] = []
        hub.register(label: "win-a") { _, _ in received.append("a") }
        hub.register(label: "win-b") { _, _ throws(KSError) in
            throw KSError(code: .internal, message: "deliberate")
        }
        hub.register(label: "win-c") { _, _ in received.append("c") }
        do {
            try hub.emit(event: "test", payload: "hi", to: nil)
        } catch {}
        #expect(received.contains("a"))
        #expect(received.contains("c"))
    }

    @Test("모든 sink 성공 시 에러 없음")
    func broadcastAllSuccess() throws {
        let hub = KSWindowEmitHub(_testIsolated: ())
        var count = 0
        hub.register(label: "x") { _, _ in count += 1 }
        hub.register(label: "y") { _, _ in count += 1 }
        try hub.emit(event: "ping", payload: "pong", to: nil)
        #expect(count == 2)
    }
}
```

### 5.2 `KSCommandRegistryRateLimitTests.swift` (추가 테스트)

```swift
@Suite("Rate Limiter 면제")
struct KSRateLimiterExemptTests {
    @Test("__ks. 프리픽스 명령은 토큰 소비하지 않음")
    func exemptPrefixBypassesRateLimit() async {
        let registry = KSCommandRegistry()
        await registry.setRateLimit(KSCommandRateLimit(rate: 1, burst: 1, exemptPrefixes: ["__ks."]))
        await registry.register("__ks.test") { _ in .success(Data("{}".utf8)) }
        await registry.register("user.cmd") { _ in .success(Data("{}".utf8)) }

        // 유저 명령으로 버스트 소진
        let r1 = await registry.dispatch(name: "user.cmd", args: Data())
        #expect(r1.isSuccess)
        let r2 = await registry.dispatch(name: "user.cmd", args: Data())
        #expect(r2.isFailure)  // rate limited

        // __ks. 명령은 여전히 통과
        let r3 = await registry.dispatch(name: "__ks.test", args: Data())
        #expect(r3.isSuccess)
    }
}
```

### 5.3 JS 런타임 통합 테스트 (수동/E2E)

| # | 시나리오 | 검증 방법 | 플랫폼 |
|---|---------|----------|--------|
| V-1 | `KalsaeError` 인스턴스 | `__KS_.invoke('invalid').catch(e => e instanceof KalsaeError)` → `true` | 전 플랫폼 |
| V-2 | `e.stack` 존재 | `__KS_.invoke('invalid').catch(e => typeof e.stack === 'string')` → `true` | 전 플랫폼 |
| V-3 | 편의 API 존재 | `typeof __KS_.window.minimize === 'function'` → `true` | macOS/Linux/iOS |
| V-4 | 타임아웃 reject | 30초 이상 미응답 명령 → `e.code === 'timeout'` | 전 플랫폼 |
| V-5 | 드래그 영역 동작 | `app-region: drag` CSS 요소 mousedown → 창 이동 시작 | Windows/macOS/Linux |
| V-6 | EmitHub 정리 | close 후 브로드캐스트 시 stale sink 호출 없음 | iOS/Android |
| V-7 | U+2028 안전 | payload에 `\u2028` 포함 emit → JS 정상 수신 | macOS/Linux/iOS |
| V-8 | 전체 빌드 | `swift build` | Windows/macOS/Linux |
| V-9 | 기존 테스트 | `swift test` 전체 통과 | 전 플랫폼 |

---

## 6. 리스크 및 완화

| 리스크 | 영향 | 완화 |
|--------|------|------|
| 편의 JS 코드 추가로 페이지 로드 시 초기화 오버헤드 증가 | JS 파싱 시간 ~1ms 미만 (120줄 추가) | 실측 기준 무시 가능. `Object.freeze`는 GC에 유리 |
| 30초 타임아웃이 `openFile` 다이얼로그에서 조기 reject | 사용자가 파일 선택 중 타임아웃 | `__ks.dialog.*` 명령은 `exemptPrefixes`에 포함되어 rate limit 면제이므로 동작은 하지만 Promise 타임아웃은 별개. 향후 per-command timeout 옵션 추가 |
| `startDrag` macOS 구현에서 `performDrag(with:)` → AppKit 이벤트 루프와 충돌 | 드래그 후 UI 멈춤 | macOS에서는 WKWebView가 직접 처리할 수 있으므로 실제 테스트 후 `mouseDown:` 리디스패치 방식으로 전환 가능 |
| Android `MainActor.run` 내 `KSWindowEmitHub` 접근이 JVM 스레드와 충돌 | 레이스 컨디션 | Android의 Swift MainActor는 Dispatch main queue에 매핑되므로 UI 스레드와 일관됨 |
| 브로드캐스트 에러 수집 후 첫 에러만 throw — 나머지 에러 정보 유실 | 디버깅 어려움 | 개별 sink 에러는 sink 내부(브리지)에서 이미 로깅됨. EmitHub은 요약만 제공 |
| `KSCommandRateLimit.exemptPrefixes` Codable 역호환 | 기존 JSON 파일에 키 없음 → decode 실패 | `init(from:)`에서 optional 디코딩 + 기본값 폴백 |

---

## 7. 미래 고려사항

1. **런타임 JS 단일 소스화**: `Sources/KalsaeCore/Resources/kalsae-runtime.js`로
   공유하고, 플랫폼별 `nativePost` 부분만 프리픽스/서픽스로 감싸는 빌드 타임
   조합 방식. 별도 RFC 추천.

2. **Swift 측 invoke 타임아웃**: `KSCommandRegistry.dispatch` 내부에서
   `Task.sleep` + `withTaskGroup` 패턴으로 핸들러 자체를 취소하면 리소스
   정리까지 보장. Swift 6.1+ `withTimeout` 도입 시 마이그레이션 용이.

3. **Per-command 타임아웃**: `invoke(cmd, args, { timeout: 60000 })` 처럼
   JS에서 개별 지정 가능한 옵션. 프로토콜 와이어에 `timeout` 필드 추가 또는
   JS 전용 처리 둘 다 가능.

4. **macOS `startDrag` 최적 구현**: `NSWindow.performDrag(with:)` 외에
   `window.setMovableByWindowBackground(true)` + CSS `app-region` 연동이
   더 네이티브일 수 있으나, WKWebView 내부에서 작동 여부를 실제 테스트해야 함.

5. **`Events.off(event, cb)` 안정성**: 현재 구현은 `listeners` Map에서 직접
   삭제하지만, `listen`이 반환하는 unsubscriber와 병행하면 Set 불일치 가능.
   → `listen` 반환값 사용을 권장하는 문서화.

---

## 8. 검증 체크리스트 (구현 전)

- [ ] §4.1 `KalsaeError` 클래스가 Windows 런타임의 것과 byte-for-byte 동일한지 확인
- [ ] §4.2 iOS/Android close 경로에서 `MainActor.run` 컨텍스트가 보장되는지 확인
- [ ] §4.3 브로드캐스트 변경이 typed throws (`throws(KSError)`) 시그니처와 호환되는지 확인
- [ ] §4.4 편의 API의 인자 형태가 `KSBuiltinCommands` 내부 디코드 구조체와 일치하는지 확인
- [ ] §4.5 타임아웃 setTimeout이 WebView GC에 의해 조기 수거되지 않는지 확인
- [ ] §4.6 `startDrag` 프로토콜 기본 구현이 기존 iOS/Android 빌드를 깨지 않는지 확인
- [ ] §4.7 `exemptPrefixes` Codable 역호환 디코딩이 빈 JSON에서도 정상인지 확인
- [ ] §4.8 `replacingOccurrences` 성능이 대용량 payload에서 문제 없는지 확인 (16MB 프레임 상한 내)
