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

The `security.commandAllowlist` field in `Kalsae.json` restricts which `@KSCommand` functions the JavaScript frontend can invoke.

- `nil` (default): All registered commands are callable from JS.
- `[]` (empty): No commands are callable — the app is purely a static web UI.
- `["cmd1", "cmd2"]`: Only `cmd1` and `cmd2` are dispatchable.

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

## Security Checklist for Production Apps

- [ ] Set a restrictive `csp` that only allows origins your app needs.
- [ ] Configure `commandAllowlist` to enumerate exactly which commands JS should call.
- [ ] Set `fs.allow` and `fs.deny` to scope file access to the minimum required paths.
- [ ] Review `shell.openExternalSchemes` — consider restricting to only needed schemes.
- [ ] Set `http.allow` to list only trusted API endpoints.
- [ ] Enable `commandRateLimit` with `rate: 100, burst: 200`.
- [ ] Set `contextMenu: "disabled"` if your app provides its own UI.
- [ ] Set `allowExternalDrop: false` (default) and handle drops via `__ks.file.drop`.
- [ ] Set `downloads.enabled: false` (default) unless your app needs downloads.
- [ ] Set `navigation.allow` to restrict which external URLs can be navigated to.
- [ ] Ensure `devtools` is `false` (default) for release builds.
