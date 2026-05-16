# RFC-002 — Linux Multi-Window Parity

| 항목 | 내용 |
|------|------|
| 상태 | 채택 (Accepted) — 구현 대기 (Linux 호스트 가용 시 착수) |
| 날짜 | 2026-05-15 (초안) · 2026-05-16 (보강·승격) |
| 영향 범위 | `Sources/CKalsaeGtk/` · `Sources/KalsaePlatformLinux/` · `Sources/Kalsae/KSApp.swift` (Linux secondary 분기) |
| 관련 | Phase 3.2 로드맵, Windows/macOS secondary 윈도우 시맨틱 |
| 호환성 | MINOR (behavioral) — 기존에 무시되던 `windows[1..]` 선언이 실제 윈도우로 표시됨 |

---

## 1. 동기 (Motivation)

Windows / macOS PAL 은 `kalsae.json` 의 `windows[]` 에 선언된 두 번째 이후 윈도우를
[KSApp.swift](../../Sources/Kalsae/KSApp.swift) L434–504 의 secondary loop 에서
인스턴스화한다. Linux PAL 은 동일 위치 L505 에서 다음 경고와 함께 무시한다:

```text
Multiple windows declared but supports single-window only; ignoring N entries.
```

원인은 [CKalsaeGtk.c](../../Sources/CKalsaeGtk/CKalsaeGtk.c) L392 `ks_gtk_host_new`
가 `gtk_application_new()` 를 인스턴스마다 호출하기 때문이다. 같은 프로세스에서
두 개의 `GtkApplication` 을 동시 실행하는 것은 GApplication 의 single-instance
계약상 정의되지 않은 동작이며, `g_application_run()` 도 한 번만 호출 가능하다.

목표는 Linux 도 Win/Mac 과 동일하게 secondary 윈도우를 표시·라우팅·상태저장하는
것이다.

_🇰🇷 Linux 만 secondary 윈도우 무시. GTK4 `GtkApplication` 분리가 원인._

---

## 2. 목표 / 비목표

### 목표
- `kalsae.json` 의 `windows[1..]` 항목을 Linux 에서도 실제 윈도우로 표시.
- Primary 윈도우의 `KSGtkHost` API (load/eval/show/hide/title/size/state…) 와
  **동등한 기능** 을 secondary 윈도우에서도 제공.
- 보안 핸들러 (`contextmenu` / `decide-policy` / CSP / `nosniff`) secondary 에도
  자동 적용.
- 윈도우 상태 영속화 (`persistState=true` 시 사이즈/최대화/풀스크린) secondary 도
  지원.
- 단축키 (`GtkShortcutController` LOCAL scope) — 창마다 독립 부착.
- 메뉴 라우팅 (`KSLinuxCommandRouter`) — secondary 윈도우 클릭도 동일 레지스트리로
  라우팅.

### 비목표
- 트레이 / autostart / single-instance / deep link 변경 (모두 프로세스 단위라
  영향 없음).
- 동적 윈도우 추가 API (JS 에서 새 윈도우 spawn) — `windows[]` 정적 선언만 지원.
- Wayland 절대 좌표 위치 복원 — 컴포지터 통제이므로 X11 best-effort 유지.

---

## 3. 채택 안 — Option B (Lightweight Secondary Spec Queue)

### 3.1 설계 원칙

1. **기존 C API 시그니처 무변경** — 모든 primary `ks_gtk_host_*` 함수는 그대로
   유지하여 regression 위험을 0 으로 만든다.
2. **하나의 GtkApplication, N 개의 GtkApplicationWindow** — GTK4 의 정상적인
   패턴. `ks_gtk_host_new` 는 그대로 `GtkApplication` 1 개를 만들고, secondary
   spec 들은 같은 application 에 attach 된다.
3. **활성화 전 등록, 활성화 시 일괄 생성** — `g_application_run()` 호출 전에
   secondary spec 들을 큐에 쌓고, `on_app_activate` 안에서 primary 윈도우를
   만든 직후 spec 들을 iterate 하며 secondary 윈도우를 추가 생성한다.

### 3.2 C 측 신설 API

[CKalsaeGtk.h](../../Sources/CKalsaeGtk/include/CKalsaeGtk.h) 에 다음을 추가한다:

```c
/* Secondary window handle. Lifetime: owned by parent KSGtkHost;
 * freed via ks_gtk_host_free on the parent (releases all strdup'd
 * fields — title / response_csp — and the GPtrArray pending_scripts,
 * including each gchar* entry inside it). */
typedef struct KSGtkSecondaryWindow KSGtkSecondaryWindow;

/* Queue a secondary-window spec on the host.
 * MUST be called BEFORE ks_gtk_host_run().
 * Returns a handle that becomes usable after activation
 * (i.e. once ks_gtk_host_run has produced the activate signal). */
KSGtkSecondaryWindow *ks_gtk_host_add_secondary_window(
    KSGtkHost     *host,
    const char    *title,
    int            width,
    int            height);

/* Per-window operations (mirror of host_* but scoped).
 * NOTE on KSGtkMessageFn ctx: for ks_gtk_host_set_message_handler the
 * ctx that the trampoline passes is the KSGtkHost* (current behavior);
 * for ks_gtk_secondary_window_set_message_handler the ctx that the
 * trampoline passes is the KSGtkSecondaryWindow*. The Swift side must
 * branch accordingly when interpreting ctx. */
void ks_gtk_secondary_window_load_uri(KSGtkSecondaryWindow *w, const char *uri);
void ks_gtk_secondary_window_eval_js(KSGtkSecondaryWindow *w, const char *script);
void ks_gtk_secondary_window_add_user_script(KSGtkSecondaryWindow *w, const char *src);
void ks_gtk_secondary_window_show(KSGtkSecondaryWindow *w);
void ks_gtk_secondary_window_hide(KSGtkSecondaryWindow *w);
void ks_gtk_secondary_window_focus(KSGtkSecondaryWindow *w);
void ks_gtk_secondary_window_reload(KSGtkSecondaryWindow *w);
void ks_gtk_secondary_window_set_title(KSGtkSecondaryWindow *w, const char *title);
void ks_gtk_secondary_window_set_size(KSGtkSecondaryWindow *w, int width, int height);

/* Scheme/message wiring. */
void ks_gtk_secondary_window_set_message_handler(
    KSGtkSecondaryWindow *w, KSGtkMessageFn cb, void *ctx);
void ks_gtk_secondary_window_register_scheme(
    KSGtkSecondaryWindow *w, KSGtkSchemeResolverFn fn, void *ctx);
void ks_gtk_secondary_window_set_response_csp(
    KSGtkSecondaryWindow *w, const char *csp);

/* Window state (mirrors ks_gtk_host_get_window_state). */
int  ks_gtk_secondary_window_get_state(
    KSGtkSecondaryWindow *w,
    int *out_w, int *out_h,
    int *out_x, int *out_y,
    int *out_maximized, int *out_fullscreen,
    int *out_has_position);
void ks_gtk_secondary_window_set_pending_restore(
    KSGtkSecondaryWindow *w,
    int w_, int h_, int x, int y,
    int maximized, int fullscreen, int has_position);
```

### 3.3 C 측 내부 구조

```c
struct KSGtkSecondaryWindowSpec {
    char         *title;
    int           width;
    int           height;
    /* 활성화 콜백이 채워주는 런타임 참조 */
    GtkWindow    *window;
    WebKitWebView *web_view;
    WebKitUserContentManager *user_cm;
    GtkShortcutController *shortcut_controller;
    /* 메시지/스킴 핸들러 (Swift 가 등록) */
    KSGtkMessageFn  on_message;
    void           *on_message_ctx;
    KSGtkSchemeResolverFn scheme_resolver;
    void           *scheme_ctx;
    char           *response_csp;
    /* 보안/복원 플래그 (primary 와 동일) */
    int             context_menu_enabled;
    int             external_drop_allowed;
    int             popup_blocking_enabled;
    GPtrArray      *pending_scripts;
    int             has_pending_restore;
    int             pending_restore_w, pending_restore_h;
    int             pending_restore_x, pending_restore_y;
    int             pending_restore_maximized;
    int             pending_restore_fullscreen;
    int             pending_restore_has_position;
};

struct KSGtkHost {
    /* ... 기존 필드 ... */
    GPtrArray *secondary_specs;  /* of KSGtkSecondaryWindow* */
};
```

`on_app_activate` 끝부분에 다음을 추가:

```c
if (host->secondary_specs) {
    for (guint i = 0; i < host->secondary_specs->len; ++i) {
        KSGtkSecondaryWindow *s =
            g_ptr_array_index(host->secondary_specs, i);
        ks_gtk_activate_secondary(app, host, s);
    }
}
```

`ks_gtk_activate_secondary` 는 `on_app_activate` 의 primary 윈도우 생성 로직을
재사용해 (1) `gtk_application_window_new(app)`, (2) user_content_manager 와
script-message-handler 등록 (`script-message-received::kb` 이지만 ctx 가
`KSGtkSecondaryWindow*` 로 다른 trampoline 사용), (3) WebKitWebView 생성·attach,
(4) 보안 시그널 (`context-menu`, `decide-policy`) 연결, (5) ks:// scheme resolver
등록, (6) pending_restore 적용, (7) shortcut controller 부착을 수행한다.

구체 시그니처:

```c
static void ks_gtk_activate_secondary(GtkApplication       *app,
                                      KSGtkHost            *host,
                                      KSGtkSecondaryWindow *spec);
```

메모리 소유권: `ks_gtk_host_free` 는 (1) `secondary_specs` GPtrArray 의 각 spec 에
대해 (2) strdup 된 `title` / `response_csp` 를 `g_free` 하고, (3) `pending_scripts`
GPtrArray 의 모든 `gchar*` 엔트리와 배열 자체를 해제, (4) GObject 참조
(`window` / `web_view` / `user_cm` / `shortcut_controller`) 는 GtkApplication 종료
시 자동 회수되므로 추가 unref 불필요. 마지막에 spec 자체를 `g_free`.

### 3.4 Swift Wrapper

`Sources/KalsaePlatformLinux/Gtk/GtkSecondaryWindow.swift` (신규):

```swift
#if os(Linux)
    internal import CKalsaeGtk
    public import Foundation
    public import KalsaeCore

    /// Primary `GtkWebViewHost` 가 소유하는 secondary 윈도우 래퍼.
    /// `GtkWebViewHost.addSecondaryWindow(...)` 로만 생성 가능.
    public final class GtkSecondaryWindowHost {
        internal let raw: OpaquePointer  // KSGtkSecondaryWindow*
        public let label: String

        internal init(raw: OpaquePointer, label: String) {
            self.raw = raw
            self.label = label
        }

        public func loadURL(_ url: String) { /* ks_gtk_secondary_window_load_uri */ }
        public func evaluate(_ script: String) { /* ... */ }
        public func addUserScript(_ source: String) { /* ... */ }
        // ... show/hide/focus/title/size/state/scheme/message handler 등
    }
#endif
```

`GtkWebViewHost.swift` 에 다음 메서드 추가:

```swift
public func addSecondaryWindow(
    label: String,
    title: String,
    width: Int32,
    height: Int32
) throws(KSError) -> GtkSecondaryWindowHost {
    guard let raw = ks_gtk_host_add_secondary_window(
        self.raw, title, width, height) else {
        throw KSError(code: .internal,
                      message: "ks_gtk_host_add_secondary_window returned NULL")
    }
    return GtkSecondaryWindowHost(raw: OpaquePointer(raw), label: label)
}
```

### 3.5 KSLinuxDemoHost 확장

[KSLinuxPlatform.swift](../../Sources/KalsaePlatformLinux/KSLinuxPlatform.swift)
L242 의 `KSLinuxDemoHost` 에 신규 init 추가:

```swift
/// Primary KSLinuxDemoHost 에 부착되는 secondary 윈도우.
/// 모든 PAL 콜은 secondary 핸들로 위임된다.
public final class KSLinuxSecondaryDemoHost: KSDemoHost {
    private let parent: KSLinuxDemoHost
    private let secondary: GtkSecondaryWindowHost
    // ... 기타 필드 (label, ipc bridge 등)

    internal init(
        parent: KSLinuxDemoHost,
        windowConfig: KSWindowConfig,
        registry: KSCommandRegistry
    ) throws(KSError) {
        self.parent = parent
        self.secondary = try parent.webview.addSecondaryWindow(
            label: windowConfig.label,
            title: windowConfig.title,
            width: Int32(windowConfig.width),
            height: Int32(windowConfig.height))
        // ... IPC bridge, scheme handler, message handler 설정
    }

    // KSDemoHost 프로토콜 구현 — 모두 self.secondary 로 위임
    public func start(url: String, devtools: Bool) throws(KSError) { ... }
    public func setAssetRoot(_ path: String) throws(KSError) { ... }
    public func setResponseCSP(_ csp: String) throws(KSError) { ... }
    public func addDocumentCreatedScript(_ source: String) throws(KSError) { ... }
    // ...
}
```

채택할 프로토콜 표면 (`Sources/KalsaeCore/PAL/KSDemoHost.swift`):
- `KSDemoHost` (필수): `registry` / `bridge` / `mainHandle` / `start` /
  `emit` / `reload` / `runMessageLoop` / `postJob` / `requestQuit` /
  `setOnBeforeClose` / `setOnSuspend` / `setOnResume` /
  `setWindowStateSaveSink` / `addDocumentCreatedScript`.
- `KSDemoHostWithAssetRoot`: `setAssetRoot(_ root: URL)`.
- `KSDemoHostWithSecurity`: `setDefaultContextMenusEnabled` /
  `setAllowExternalDrop` / `installSecurityHandlers`.
- `KSDemoHostWithResponseCSP`: `setResponseCSP`.

위임 규칙:
- `runMessageLoop()` → 메인 루프는 parent 가 소유. secondary 인스턴스에서는
  `0` 을 반환하고 once-only `KSLog.warning` 으로 "runMessageLoop called on
  secondary host; primary owns the loop" 만 남긴다. iOS/Android 의
  `unsupportedPlatform` 패턴과는 다르다 — secondary 는 정상 호스트지만 루프
  소유권만 없는 것이므로 throw 하지 않는다.
- `requestQuit()` → `parent.requestQuit()` 위임 (전체 앱 종료).
- `bridge` → secondary 전용 신규 `GtkBridge` 인스턴스 (windowLabel 은 자체).
- `setOnSuspend` / `setOnResume` → no-op (Linux 는 시스템 전원 이벤트로만
  발화되며 secondary 단위 hook 없음). 호출 자체는 허용.

### 3.6 KSApp.swift Linux 분기

L505 의 경고 분기를 다음으로 교체. 본 분기는 macOS secondary loop
([KSApp.swift L484-505](../../Sources/Kalsae/KSApp.swift#L484-L505)) 를 템플릿으로
재사용하며, 다음 심볼은 모두 macOS 분기에서 이미 사용 중인 동일 헬퍼/변수다:
- `secondaryWrappers: [any KSDemoHost]` — [KSApp.swift L434](../../Sources/Kalsae/KSApp.swift#L434) 의 로컬 변수.
  뒤에서 [L618](../../Sources/Kalsae/KSApp.swift#L618) 의 `secondaryHosts:` 인자로 전달되어 KSApp
  인스턴스가 retain 한다 (lifetime 자동 보전).
- `decideServingMode(...)` / `resolveStartURL(...)` — KSApp 내부 헬퍼.
- `cspScript` — primary 분기에서 `KSBootOrchestrator.cspInjectionScript(...)` 로 이미 생성된 로컬 변수.

```swift
#elseif os(Linux)
    if let primary = wrapper as? KSLinuxDemoHost {
        for secondaryConfig in config.windows where secondaryConfig.label != window.label {
            let secStateStore = secondaryConfig.persistState
                ? KSWindowStateStore.standard(appIdentifier: config.app.identifier)
                : nil
            let secRestoredState = secStateStore?.load(label: secondaryConfig.label)
            let sec = try KSLinuxSecondaryDemoHost(
                parent: primary,
                windowConfig: secondaryConfig,
                registry: registry)
            let secMode = decideServingMode(
                config: config, urlOverride: nil,
                windowURL: secondaryConfig.url,
                primaryAssetRoot: assetRoot,
                primaryServedRoot: servedRoot)
            if case .virtualHost(let secRoot) = secMode {
                try sec.setAssetRoot(secRoot)
            }
            try sec.setResponseCSP(config.security.csp)
            try sec.addDocumentCreatedScript(cspScript)
            if let store = secStateStore, let state = secRestoredState {
                sec.applyPendingRestore(state)
            }
            if let store = secStateStore {
                let lbl = secondaryConfig.label
                sec.setWindowStateSaveSink { state in
                    _ = store.save(label: lbl, state: state)
                }
            }
            let secURL = resolveStartURL(
                config: config, urlOverride: nil,
                windowURL: secondaryConfig.url,
                primaryAssetRoot: assetRoot,
                primaryServedRoot: servedRoot)
            try sec.start(url: secURL, devtools: config.security.devtools)
            secondaryWrappers.append(sec)
        }
    }
#elseif os(iOS) || os(Android)
    // 경고 유지 — 모바일은 단일 윈도우 모델
```

---

## 4. 대안 (Considered Alternatives)

### Option A — 풀 리팩토링 (KSGtkHost → KSGtkApp + KSGtkWindow[])

- 장점: 더 깨끗한 추상화, primary 와 secondary 가 대칭.
- 단점: ~15개 기존 C 함수 시그니처 변경 → Swift wrapper 전체 재작성. Regression
  표면 거대. Linux production 영향.
- 결론: 거부. 호스트 OS 가 Linux 가 아닌 상태에서 안전하게 진행 불가.

### Option C — 동적 윈도우 (JS spawn API)

- 장점: 풍부한 기능.
- 단점: 보안 모델 (CSP/scheme/명령 화이트리스트) 의 spawn-time 일관성 보장이
  복잡. RFC 별도 필요.
- 결론: 비목표.

---

## 5. 마이그레이션·호환성

- 기존 single-window Linux 앱: 영향 없음 (`windows[]` 항목 1개 → 경로 동일).
- 기존 multi-window 선언 Linux 앱: 경고 → 실제 윈도우 표시로 동작 변경.
  SemVer 분류: **MINOR (behavioral)** — API 시그니처는 불변이고, "선언했는데
  무시되던 것이 동작" 이라 일반적인 사용자 기대에 부합. 단 사용자가
  `windows[]` 에 placeholder 를 두고 있었다면 두 번째 윈도우가 갑자기 표시되므로
  CHANGELOG 의 "Behavioral Changes" 섹션에 명시한다.
- Opt-out flag 는 도입하지 않는다. 검토했으나 (`KALSAE_LINUX_DISABLE_SECONDARY=1`
  같은 env 변수), 선언된 윈도우를 무시하는 것이 "버그 수정" 이지 행위 변경이
  아니라는 합의에 따라 거부.

---

## 6. 테스트 계획

신규 테스트:

- [Tests/KalsaePlatformLinuxTests/KSLinuxSecondaryWindowTests.swift](../../Tests/KalsaePlatformLinuxTests/)
  - `@Test func addSecondaryWindow_returnsLiveHandle()` — 큐 등록 후 핸들 nil 아님
  - `@Test func secondaryEvalJS_routesViaSecondaryUCM()` — primary 와 격리 확인
  - `@Test func secondaryWindowState_persistsAndRestores()` — `applyPendingRestore`
    → `getState` 라운드트립
  - `@Test func secondaryWindowURL_resolvesVirtualHostIndependently()` — 각 윈도우의
    `setAssetRoot` 가 독립 적용
  - `@Test func secondaryCloseDoesNotQuitApp()` — secondary 윈도우 close 시 primary
    가 살아있고 메인 루프가 계속 동작 (§7 Q1 합의).
  - `@Test func primaryCloseQuitsAllSecondaries()` — primary close → GtkApplication
    semantics 에 따라 모든 secondary 가 자연 종료 + 메인 루프 quit (§7 Q2).

CI: [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) Linux 잡으로
컴파일·테스트. Wayland / X11 실제 표시 검증은 수동 (Ubuntu 22.04 GNOME).

---

## 7. 미해결 질문

- **Q1.** secondary 윈도우 close-request 시 primary 만 살아있어도 OK? (현재 primary
  close → app quit). 답: 모든 윈도우 close 시에만 app quit (GtkApplication 기본).
  구현 시 close-request 핸들러를 secondary 에도 동일 적용.
- **Q2.** primary 윈도우 close 시 secondary 들을 강제 close 할지? 답: GtkApplication
  semantics 를 따라 자연스럽게 quit; 별도 처리 없음.
- **Q3.** secondary 의 trayMenu / appMenu 노출 정책? 답: 트레이는 프로세스 단위로
  primary 만 소유; appMenu 도 동일. windowMenu 만 per-window.

---

## 8. 구현 순서 (참고)

1. C: `KSGtkSecondaryWindow` 구조체 + spec queue + helper trampoline 추가.
2. C: `ks_gtk_host_add_secondary_window` + `ks_gtk_activate_secondary` 작성.
3. C: per-window `secondary_window_*` API 구현.
4. Swift: `GtkSecondaryWindowHost` 래퍼 작성.
5. Swift: `GtkWebViewHost.addSecondaryWindow` 추가.
6. Swift: `KSLinuxSecondaryDemoHost` 작성, `KSDemoHost` 프로토콜 위임.
7. Swift: `KSApp.swift` Linux 분기 secondary loop 추가.
8. 테스트: 4종 추가 + Linux CI 통과 확인.
9. 수동 검증: Ubuntu GNOME + KDE 에서 2-윈도우 데모 실행, 메뉴 라우팅 / 상태저장 /
   단축키 / 보안 핸들러 동작 확인.

---

_🇰🇷 Linux secondary 윈도우는 기존 `GtkApplication` 에 spec queue 를 더해 같은
앱 안에서 N 개의 `GtkApplicationWindow` 를 생성하는 가벼운 접근으로 구현한다.
기존 C API 무변경, 신규 함수만 추가. 실제 코드 변경은 Linux 호스트 가용 시점에
착수._
