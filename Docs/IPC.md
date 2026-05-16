# Kalsae IPC Protocol

## Overview

Kalsae uses a JSON-based IPC protocol between the JavaScript frontend (running in the WebView) and the Swift host process. The protocol is inspired by Tauri's v2 IPC design.

## Wire Format

All messages are JSON-encoded `KSIPCMessage` structures:

```typescript
interface KSIPCMessage {
  kind: "invoke" | "response" | "event";
  id?: string;       // Correlates invoke with response (required for invoke/response)
  name?: string;     // Command name (invoke) or event name (event)
  payload?: any;     // JSON-encoded payload
  isError?: boolean; // true when payload encodes an error (response only)
}
```

### Message Types

#### `invoke` (JS → Swift)

Calls a registered `@KSCommand` handler:

```json
{
  "kind": "invoke",
  "id": "req-001",
  "name": "greet",
  "payload": { "name": "World" }
}
```

#### `response` (Swift → JS)

Replies to a previous `invoke`:

```json
{
  "kind": "response",
  "id": "req-001",
  "payload": { "greeting": "Hello, World!" },
  "isError": false
}
```

On error:

```json
{
  "kind": "response",
  "id": "req-001",
  "payload": {
    "code": "commandNotFound",
    "message": "No handler registered for 'unknown'"
  },
  "isError": true
}
```

#### `event` (Swift → JS or JS → Swift)

Fire-and-forget event:

```json
{
  "kind": "event",
  "name": "__ks.deepLink.openURL",
  "payload": { "url": "myapp://open?file=doc.pdf" }
}
```

## JavaScript API

The framework injects a `window.__KS_` object into every page:

### `__KS_.invoke(name, args)`

```typescript
// Invoke a command and await the result
const result = await __KS_.invoke("greet", { name: "World" });
```

- Returns a `Promise` that resolves with the command's return value.
- Rejects with an error object on failure.

### `__KS_.listen(name, callback)`

```typescript
// Listen for events from the host
const unlisten = __KS_.listen("menu", (payload) => {
  console.log("Menu clicked:", payload.command);
});
```

- Returns an `unlisten` function to stop listening.

### `__KS_.emit(name, payload)`

```typescript
// Emit an event to the host
__KS_.emit("customEvent", { key: "value" });
```

## Built-in Commands

The host registers the following built-in command namespaces during boot:

### `__ks.window.*`

State / lifecycle:

| Command | Description |
|---|---|
| `__ks.window.minimize` | Minimize the window |
| `__ks.window.maximize` | Maximize the window |
| `__ks.window.restore` | Restore from minimized/maximized |
| `__ks.window.toggleMaximize` | Toggle the maximized state |
| `__ks.window.show` | Show the window |
| `__ks.window.hide` | Hide the window |
| `__ks.window.focus` | Bring the window to front and focus it |
| `__ks.window.close` | Close the current window |
| `__ks.window.reload` | Reload the WebView contents |
| `__ks.window.center` | Center the window on screen |
| `__ks.window.startDrag` | Start a native window drag (desktop only; mobile no-op) |
| `__ks.window.setCloseInterceptor` | When enabled, close requests fire the `__ks.window.beforeClose` event instead of closing immediately |
| `__ks.window.isMinimized` | Check if window is minimized |
| `__ks.window.isMaximized` | Check if window is maximized |
| `__ks.window.isFullscreen` | Check if window is fullscreen |
| `__ks.window.isNormal` | True when none of minimized/maximized/fullscreen apply |

Geometry / appearance:

| Command | Description |
|---|---|
| `__ks.window.setSize` | Set window dimensions (1..=65535) |
| `__ks.window.getSize` | Get current window dimensions |
| `__ks.window.setMinSize` | Set the minimum window size |
| `__ks.window.setMaxSize` | Set the maximum window size |
| `__ks.window.setPosition` | Set window position (multi-monitor coordinates allowed) |
| `__ks.window.getPosition` | Get current window position |
| `__ks.window.setFullscreen` | Toggle fullscreen mode |
| `__ks.window.setAlwaysOnTop` | Set always-on-top state |
| `__ks.window.setTitle` | Set the window title |
| `__ks.window.setTheme` | Set window theme (`light` / `dark` / `system`) |
| `__ks.window.setBackgroundColor` | Set background color (RGBA, 0..=255 each) |
| `__ks.window.setZoom` | Set the WebView zoom factor |
| `__ks.window.getZoom` | Get the WebView zoom factor |

Display / taskbar:

| Command | Description |
|---|---|
| `__ks.window.displays` | Enumerate connected displays |
| `__ks.window.currentDisplay` | Display the current window resides on |
| `__ks.window.setTaskbarProgress` | Taskbar progress indicator (Windows only; other platforms no-op) |
| `__ks.window.setOverlayIcon` | Taskbar overlay icon (Windows only; `iconPath` validated against `security.fs`) |

WebView features:

| Command | Description |
|---|---|
| `__ks.window.print` | Show the print UI (`systemDialog?: bool`) |
| `__ks.window.capturePreview` | Capture window preview as base64 PNG/JPEG |

#### Multi-window (v0.3+)

| Command | Args | Returns | Description |
|---|---|---|---|
| `__ks.window.create` | `KSWindowConfig` | `{ label }` | Create a new native window. Optional `url` field is loaded immediately. **Limitation:** the new window inherits structural settings only — no CSP header injection, no virtual host (`https://app.kalsae/` / `ks://app/`), no `persistState`, no deep-link handlers. Caller must pass an explicit URL and apply security policy in JS. For full security, declare windows up front in `config.windows`. |
| `__ks.window.list` | — | `[{ label }]` | Return all currently open window labels. |
| `__ks.window.current` | — | `{ label }` | Return the label of the window from which the IPC frame was sent (resolved via `KSInvocationContext.windowLabel` task-local). Throws `invalidArgument` when called outside an IPC dispatch. |
| `__ks.window.emit` | `{ event, payload, target? }` | — | Emit an event to a specific window (`target` = label) or broadcast to all windows when `target` is `null`/omitted. |

### `__ks.shell.*`

| Command | Description |
|---|---|
| `__ks.shell.openExternal` | Open URL in default browser |
| `__ks.shell.showItemInFolder` | Reveal file in system file manager |
| `__ks.shell.moveToTrash` | Move file to trash |

### `__ks.clipboard.*`

| Command | Description |
|---|---|
| `__ks.clipboard.readText` | Read text from system clipboard |
| `__ks.clipboard.writeText` | Write text to system clipboard |
| `__ks.clipboard.clear` | Clear the system clipboard |
| `__ks.clipboard.hasFormat` | Check whether the clipboard currently holds a given format |

### `__ks.dialog.*`

| Command | Description |
|---|---|
| `__ks.dialog.openFile` | Native open-file dialog (single or multiple) |
| `__ks.dialog.saveFile` | Native save-file dialog |
| `__ks.dialog.selectFolder` | Native folder-picker dialog |
| `__ks.dialog.message` | Native message dialog (info/warning/error/question) |

> `defaultDirectory` arguments on `openFile` / `saveFile` / `selectFolder` are validated against `security.fs` (RFC-002 §2.x).

### `__ks.app.*` / `__ks.environment` / `__ks.log`

| Command | Description |
|---|---|
| `__ks.app.quit` | Request a graceful quit of the host process |
| `__ks.environment` | Return `{ os, arch, platform, osVersion, locale, appVersion, kalsaeVersion }` |
| `__ks.log` | Forward a `{ level, message }` entry to the native logger (`trace`/`debug`/`info`/`warn`/`error`) |

### `__ks.notification.*`

| Command | Description |
|---|---|
| `__ks.notification.post` | Post a desktop notification |
| `__ks.notification.cancel` | Cancel a notification |
| `__ks.notification.requestPermission` | Request notification permission |

### `__ks.fs.*`

| Command | Description |
|---|---|
| `__ks.fs.readTextFile` | Read a UTF-8 text file |
| `__ks.fs.writeTextFile` | Write a UTF-8 text file |
| `__ks.fs.readFile` | Read a binary file (returns base64) |
| `__ks.fs.writeFile` | Write a binary file (base64 input) |
| `__ks.fs.exists` | Check if a path exists |
| `__ks.fs.metadata` | Get file metadata (size, mtime, kind) |
| `__ks.fs.readDir` | List directory contents |
| `__ks.fs.createDir` | Create a directory (`recursive?: bool`) |
| `__ks.fs.remove` | Remove a file or directory (`recursive?: bool`) |
| `__ks.fs.rename` | Rename / move a file or directory |
| `__ks.fs.copyFile` | Copy a file |

> All `__ks.fs.*` paths are validated against `security.fs` (`allow` / `deny` glob patterns). The standardised, expanded path is forwarded to the platform layer to prevent TOCTOU bypass (RFC-002 §2).

### `__ks.http.fetch`

| Command | Description |
|---|---|
| `__ks.http.fetch` | Make an HTTP request (method, url, headers, body) |

### `__ks.environment.*`

The single `__ks.environment` query (see `__ks.app.*` table above) returns all environment fields (`os`, `arch`, `platform`, `osVersion`, `locale`, `appVersion`, `kalsaeVersion`) in one call. Per-field accessors are not registered.

### `__ks.autostart.*`

| Command | Description |
|---|---|
| `__ks.autostart.isEnabled` | Check if autostart is enabled |
| `__ks.autostart.enable` | Enable autostart |
| `__ks.autostart.disable` | Disable autostart |

### `__ks.deepLink.*`

| Command | Description |
|---|---|
| `__ks.deepLink.register` | Register a custom URL scheme |
| `__ks.deepLink.unregister` | Unregister a custom URL scheme |
| `__ks.deepLink.isRegistered` | Check whether a scheme is currently registered |
| `__ks.deepLink.currentLaunchURLs` | Return URLs that launched the app, if any |

## Events

The host emits the following events to the JS frontend:

| Event | Payload | Description |
|---|---|---|
| `menu` | `{ command, itemID }` | Native menu item clicked |
| `__ks.deepLink.openURL` | `{ url }` | Deep link URL received |
| `__ks.file.drop` | `{ paths: string[] }` | Files dropped onto window (when `security.allowExternalDrop` is `false`) |
| `__ks.webview.downloadStarting` | `{ url, mimeType }` | Download initiated |
| `__ks.window.beforeClose` | `{ label }` | Fired when a close request is intercepted via `__ks.window.setCloseInterceptor`. JS may call `__ks.window.close` to honour, or do nothing to cancel. |
| `__ks.window.created` | `{ label }` | A new window was created. Broadcast to all open windows (Windows / macOS, v0.3+). |
| `__ks.window.closed` | `{ label }` | A window was closed. Broadcast to all remaining windows (Windows / macOS, v0.3+). |

## Threading Model

```
JS Thread (WebView)          UI Thread (MainActor)      Background Thread
┌─────────────────┐         ┌────────────────────┐     ┌──────────────────┐
│ __KS_.invoke()  │──JSON──▶│ handleInbound()    │     │                  │
│                 │         │  decode frame       │     │  Task.detached { │
│                 │         │  hop → background   │──▶  │    registry.     │
│                 │         │                     │     │    dispatch()    │
│                 │         │  sendResponse()     │◀──  │  }               │
│                 │◀──JSON──│  (via MainHop)      │     │                  │
└─────────────────┘         └────────────────────┘     └──────────────────┘
```

- **Inbound frames** are received on the UI thread (WebView message handler).
- **Command dispatch** runs on a background thread via `Task.detached`.
- **Response posting** hops back to the UI thread via the platform's `MainHop`:
  - Windows: `PostMessageW(WM_KS_JOB)`
  - macOS: `Task { @MainActor }` (AppKit runloop pumps Swift concurrency)
  - Linux: `g_idle_add`

## Error Codes

| Code | Description |
|---|---|
| `commandNotFound` | No handler registered for the command name |
| `commandNotAllowed` | Command is not in the allowlist |
| `commandDecodeFailed` | Failed to decode command arguments |
| `commandEncodeFailed` | Failed to encode command result |
| `commandExecutionFailed` | Command handler threw an error |
| `rateLimited` | Command rate limit exceeded |
| `unsupportedPlatform` | Operation not available on this platform |
| `configInvalid` | Configuration validation failed |
| `internal` | Internal framework error |

## Security

- **Frame size limit**: 16 MB maximum inbound frame size.
- **Rate limiting**: Token-bucket algorithm, configurable via `security.commandRateLimit`.
- **Allowlist**: Only user commands listed in `security.commandAllowlist` are dispatchable (`nil`/`[]` = deny-all since 0.4.0). Built-in `__ks.*` commands are registered via `registerInternal()` and bypass this gate (they are governed by their own scopes such as `shell`, `notifications`, `fs`, `http`).
- **XSS protection**: JSON strings are escaped for `</script>` and Unicode line/paragraph separators.
