# Kalsae Security Model

## Philosophy

Kalsae follows a **default-deny** security philosophy, inspired by Tauri's security model. The framework ships with conservative defaults that minimize the attack surface. App developers explicitly opt into capabilities their frontend code needs.

## Security Layers

### 1. Content Security Policy (CSP)

A strict CSP is injected into every page served by the virtual host:

```
default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';
img-src 'self' data:; connect-src 'self' ks://localhost
```

- **Windows**: CSP is applied via `WebResourceRequested` HTTP response headers on `https://app.kalsae/` virtual host.
- **Linux/macOS/iOS/Android**: CSP is injected as a `<meta>` tag via `addDocumentCreatedScript`.
- **Customization**: Apps can override the CSP via `security.csp` in `Kalsae.json`.

### 2. Command Allowlist

The `security.commandAllowlist` field in `Kalsae.json` restricts which user `@KSCommand` functions the JavaScript frontend can invoke. **Built-in `__ks.*` commands always bypass this gate** — they are registered via `registerInternal()` and are governed instead by their dedicated scopes (`shell`, `notifications`, `fs`, `http`, `downloads`, `navigation`, `secret`).

- `nil` (omitted) or `[]` (empty): **deny-all for user commands.** The app may still call `__ks.*` built-ins per their scopes. This is the default since 0.4.0.
- `["cmd1", "cmd2"]`: Only `cmd1` and `cmd2` are dispatchable.
- `commandAllowlistAll: true` (separate field): legacy escape hatch — allow every registered user command. **Not recommended for production**; prefer enumerating commands explicitly.

The allowlist is applied **before** user command registration in the boot sequence, ensuring no race condition where a command could be invoked before the allowlist is set.

### 3. Filesystem Access (`security.fs`)

```json
{
  "security": {
    "fs": {
      "allow": ["$APP/data/**", "$HOME/.config/myapp/**"],
      "deny": ["$APP/data/secrets/**"]
    }
  }
}
```

- Uses glob-style patterns with platform-aware path placeholders:
  - `$APP` — Application data directory
  - `$HOME` — User home directory
  - `$DOCS` — User documents directory
  - `$TEMP` — System temp directory
- `deny` patterns are evaluated after `allow` patterns (deny wins).
- Default: empty `allow` and `deny` — no filesystem access.

### 4. Shell Integration (`security.shell`)

Controls `__ks.shell.*` JS commands:

| Field | Type | Default | Description |
|---|---|---|---|
| `openExternalSchemes` | `[String]?` | `["http", "https", "mailto"]` | Allowed URL schemes for `openExternal`. `null` = all schemes allowed. |
| `showItemInFolder` | `Bool` | `true` | Allow revealing files in system file manager. |
| `moveToTrash` | `Bool` | `true` | Allow moving files to trash. |
| `fsScope` | `KSFSScope` | empty (deny-all) | **(RFC-002 §2.1)** Path-level scope applied to `showItemInFolder`/`moveToTrash` arguments. An empty scope denies all paths. Existing apps using these commands MUST add explicit `allow` patterns. |

> **Migration note (RFC-002):** `KSShellScope.fsScope` is new in this release.
> Apps using `__ks.shell.showItemInFolder` or `__ks.shell.moveToTrash` must add
> path patterns explicitly, e.g.:
>
> ```json
> {
>   "security": {
>     "shell": {
>       "fsScope": { "allow": ["$HOME/Documents/**", "$DOCS/**"] }
>     }
>   }
> }
> ```
>
> Without an `allow` list, both commands return `fsScopeDenied` for every
> argument (default-deny).

### 5. HTTP Fetch (`security.http`)

Controls `__ks.http.fetch` — the JS-side HTTP client.

```json
{
  "security": {
    "http": {
      "allow": ["https://api.example.com/**"]
    }
  }
}
```

- Default: empty `allow` — no HTTP fetch access.
- Patterns are URL globs (scheme + host + path).

### 6. Notifications (`security.notifications`)

Controls `__ks.notification.*` JS commands:

| Field | Type | Default | Description |
|---|---|---|---|
| `post` | `Bool` | `true` | Allow posting desktop notifications. |
| `cancel` | `Bool` | `true` | Allow canceling notifications. |
| `requestPermission` | `Bool` | `true` | Allow requesting notification permission. |

### 7. Navigation Scope (`security.navigation`)

Controls top-level WebView navigation:

```json
{
  "security": {
    "navigation": {
      "allow": ["https://example.com/**"],
      "openInBrowser": true
    }
  }
}
```

- Empty `allow` = no restriction (existing behavior).
- Non-empty `allow` = only matching URLs navigate in the WebView; others are cancelled.
- `openInBrowser`: when `true`, blocked navigations open in the user's default browser.

### 8. Downloads (`security.downloads`)

Controls WebView download capability:

```json
{
  "security": {
    "downloads": {
      "enabled": true
    }
  }
}
```

- Default: `enabled: false` — downloads are blocked.
- When enabled, the host emits `__ks.webview.downloadStarting` events for JS observation.

### 9. Context Menu (`security.contextMenu`)

| Value | Description |
|---|---|
| `"default"` | Native browser-style context menu (cut/copy/paste/inspect). |
| `"disabled"` | Native context menu completely hidden. Page can still render custom JS menus. |

### 10. External Drop (`security.allowExternalDrop`)

- `false` (default): OS file drops are intercepted by the host and emitted as `__ks.file.drop` events. The WebView's built-in drop is disabled.
- `true`: OS files can be dropped directly into the WebView.

### 11. Rate Limiting (`security.commandRateLimit`)

```json
{
  "security": {
    "commandRateLimit": {
      "rate": 100,
      "burst": 200
    }
  }
}
```

- Token-bucket algorithm.
- `rate`: Tokens replenished per second.
- `burst`: Maximum accumulated tokens (allows short bursts above the rate).
- `null` (default): Rate limiting disabled.
- Recommended production values: `rate: 100, burst: 200`.

### 12. IPC Frame Size Limit

- Maximum inbound IPC frame: **16 MB** (`KSIPCBridgeCore.maxFrameBytes`).
- Frames exceeding this limit are silently dropped to prevent OOM/CPU DoS attacks.

### 13. DevTools

- `security.devtools: true` enables WebView DevTools in debug builds.
- In release builds, DevTools are **always disabled** regardless of this setting.

### 14. IPC Argument Path/URL Validation (RFC-002)

All IPC commands that accept a path or URL from JavaScript validate it against
the relevant scope **before** the value crosses into PAL code. After validation
the standardised, expanded value is forwarded to the platform layer (no
TOCTOU window between check and use).

| Command | Argument | Scope checked | Behaviour on deny |
|---|---|---|---|
| `__ks.shell.showItemInFolder` | `url` | `security.shell.fsScope` | `fsScopeDenied` |
| `__ks.shell.moveToTrash` | `url` | `security.shell.fsScope` | `fsScopeDenied` |
| `__ks.window.setOverlayIcon` | `iconPath` | `security.fs` | `fsScopeDenied` |
| `__ks.window.create` | `url` | `security.navigation` | `commandNotAllowed` (validated **before** backend creates the window — no leak) |
| `__ks.window.setSize` | `width` / `height` | range `1..=65535` | `invalidArgument` |
| `__ks.window.setPosition` | `x` / `y` | none (multi-monitor compatibility — `Int` type prevents NaN/Inf) | — |
| `__ks.dialog.openFile` | `defaultDirectory` | `security.fs` | `fsScopeDenied` |
| `__ks.dialog.saveFile` | `defaultDirectory` | `security.fs` | `fsScopeDenied` |
| `__ks.dialog.selectFolder` | `defaultDirectory` | `security.fs` | `fsScopeDenied` |
| `__ks.notification.post` | `iconPath` | `security.fs` | `fsScopeDenied` |

> Empty `KSNavigationScope.allow` retains the legacy "no restriction" semantics
> for `__ks.window.create`. To actually restrict creatable URLs, set
> `security.navigation.allow` to an explicit list.

### 15. External Config Override (Debug-only)

`KSApp.boot()` can read `KALSAE_CONFIG` / `--kalsae-config` to override the
config path. To prevent supply-chain hijacking in shipped apps, this override
is honoured **only in debug builds** (`#if DEBUG`). Release binaries always
load the bundled `kalsae.json` and ignore the environment variable / argument.

### 16. Credential Store (`security.secret`)

토큰·API 키 등 민감한 비밀은 OS의 보안 자격증명 보관소(macOS/iOS:
Keychain, Windows: Credential Manager, Linux: libsecret Secret Service
— GNOME Keyring / KWallet / KeePassXC)에 위임 저장한다. JS는
`window.__KS_.secret.{set,get,getString,delete,list}` 로 호출하며 다음
게이트를 통과해야 한다:

| Field | Default | 효과 |
|---|---|---|
| `enabled` | `false` | 전체 켜기/끄기 |
| `allowedServices` | `[]` | 사용 가능한 `service` 화이트리스트 (`"*"` = 모두) |
| `maxSecretBytes` | `65536` | 값 크기 상한 |
| `allowList` | `true` | `list()` 허용 여부 |
| `allowDelete` | `true` | `delete()` 허용 여부 |

호스트는 `service` 앞에 `KSConfig.app.identifier`를 자동으로 prefix하여
다른 앱의 저장소를 침범하지 못한다. wire payload는 base64로 인코딩되고
JS API는 `Uint8Array`/문자열 양쪽을 받는다. 지원 플랫폼: macOS, iOS,
Windows. Linux/Android는 현재 `unsupportedPlatform` 을 던진다.

### 17. User Scripts (`security.userScripts`)

Kalsae는 Tauri v2의 `initialization_script`에 대응하는 사용자 스크립트
주입 API를 제공한다. 모든 등록은 origin 화이트리스트 기반의 **default-deny**
정책을 따른다.

```json
{
  "security": {
    "userScripts": {
      "allowOrigins": ["https://app.kalsae", "ks://app", "https://*.example.org"],
      "scripts": [
        {
          "id": "telemetry-boot",
          "path": "scripts/boot.js",
          "injectionTime": "documentStart",
          "forMainFrameOnly": true,
          "origins": ["https://app.kalsae", "ks://app"]
        }
      ]
    }
  }
}
```

| 필드 | 타입 | 기본 | 설명 |
|---|---|---|---|
| `allowOrigins` | `[String]` | `[]` | 사용자 스크립트가 실행될 수 있는 origin glob 화이트리스트. **비어 있으면 어떤 스크립트도 등록 불가** (default-deny). |
| `scripts` | `[KSUserScript]` | `[]` | 부팅 시 자동 등록되는 선언 스크립트. |
| `scripts[].id` | `String` | `""` | 비어 있으면 부팅 시 `config-<uuid>`로 자동 생성. 중복 금지. |
| `scripts[].source` | `String?` | `nil` | 인라인 JS 본문. `path`와 **정확히 하나만** 지정. |
| `scripts[].path` | `String?` | `nil` | resourceRoot 상대 경로. `..`/절대 경로 금지. |
| `scripts[].injectionTime` | `"documentStart"` \| `"documentEnd"` | `documentStart` | 주입 시점. `documentEnd`는 `DOMContentLoaded` 폴리필로 구현됨. |
| `scripts[].forMainFrameOnly` | `Bool` | `false` | `true`면 최상위 프레임에만 주입. |
| `scripts[].origins` | `[String]` | `[]` | 이 스크립트가 활성화될 origin. **모든 항목이 `allowOrigins`의 부분집합이어야 한다.** |

**보안 모델 — 다층 가드:**

1. **Config validation** — 부팅 시 `KSConfigLoader`가 `allowOrigins`/origin
   부분집합/source⊕path/`..` traversal/중복 ID를 검증한다. 위반 시
   `configInvalid`.
2. **Runtime API gate** — `KSApp.addUserScript(_:)`도 동일한 검증을 적용한다.
   `allowOrigins` 위반 시 `permissionDenied`.
3. **IIFE wrapper** — 모든 사용자 스크립트는 `KSUserScriptWrapper`가 IIFE로
   래핑한다. 래퍼는 (a) `KSHTTPScope` 글롭으로 현재 페이지 origin을 검사하고
   미일치 시 본문을 실행하지 않으며, (b) `try/catch`로 호스트 페이지 격리를
   유지하고, (c) `documentEnd`일 때 `readyState`/`DOMContentLoaded` 폴리필을
   적용한다.
4. **Main world 전용** — 모든 PAL은 기존 `addDocumentCreatedScript` 경로를
   재사용한다 (WKUserScript / WebView2 `AddScriptToExecuteOnDocumentCreatedAsync` /
   WebKitGTK `webkit_user_content_manager_add_script` / Android documentStart 큐).
   별도 isolated world는 제공하지 않는다 — Tauri의 `initialization_script`과
   동일한 시맨틱.

**런타임 API:**

```swift
import Kalsae

let id = try app.addUserScript(
    KSUserScript(
        source: "window.__bootedAt = Date.now();",
        injectionTime: .documentStart,
        origins: ["https://app.kalsae"]
    )
)
```

- 반환 ID는 검증 통과 후 (UUID 자동 할당 포함) 영구 식별자.
- 이미 로드된 페이지에는 적용되지 않으며 **다음 navigation부터** 효력이 발생한다 (Tauri와 동일).
- 한번 등록된 스크립트는 프로세스 수명 동안 제거할 수 없다 (WebView2 비동기 script-id 관리 / Android documentStart 큐 한계로 인한 의도된 제약). 실험성 스크립트는 origin 게이트로 사실상 무력화하는 패턴을 권장한다.

**일반적 실수:**

- ❌ `allowOrigins`를 비워둔 채 `scripts` 정의 → `configInvalid`.
- ❌ `scripts[].origins`에 `allowOrigins`에 없는 패턴 사용 → `configInvalid`.
- ❌ `source`와 `path` 동시 지정 → `configInvalid`.
- ❌ `path: "../../etc/passwd"` 또는 절대 경로 → `configInvalid`.
- ❌ 동일 `id` 두 번 등록 → `configInvalid` (선언) / `permissionDenied` (런타임).

## Security Checklist for Production Apps

- [ ] Set a restrictive `csp` that only allows origins your app needs.
- [ ] Configure `commandAllowlist` to enumerate exactly which user commands JS should call. Do **not** rely on `commandAllowlistAll: true` in production.
- [ ] Set `fs.allow` and `fs.deny` to scope file access to the minimum required paths.
- [ ] Review `shell.openExternalSchemes` — consider restricting to only needed schemes.
- [ ] Set `http.allow` to list only trusted API endpoints.
- [ ] Enable `commandRateLimit` with `rate: 100, burst: 200`.
- [ ] Set `contextMenu: "disabled"` if your app provides its own UI.
- [ ] Set `allowExternalDrop: false` (default) and handle drops via `__ks.file.drop`.
- [ ] Set `downloads.enabled: false` (default) unless your app needs downloads.
- [ ] Set `navigation.allow` to restrict which external URLs can be navigated to.
- [ ] Ensure `devtools` is `false` (default) for release builds.
- [ ] Set `userScripts.allowOrigins` only when you actually use user scripts; leave empty otherwise. Prefer `path` over inline `source` and pin each script's `origins` to the smallest possible subset.
