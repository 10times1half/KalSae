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

| Command | Description |
|---|---|
| `__ks.window.close` | Close the current window |
| `__ks.window.minimize` | Minimize the window |
| `__ks.window.maximize` | Maximize the window |
| `__ks.window.unmaximize` | Restore from maximized |
| `__ks.window.isMaximized` | Check if window is maximized |
| `__ks.window.show` | Show the window |
| `__ks.window.hide` | Hide the window |
| `__ks.window.setTitle` | Set the window title |
| `__ks.window.getTitle` | Get the current window title |
| `__ks.window.setSize` | Set window dimensions |
| `__ks.window.getSize` | Get current window dimensions |
| `__ks.window.setPosition` | Set window position |
| `__ks.window.getPosition` | Get current window position |
| `__ks.window.setFullscreen` | Toggle fullscreen mode |
| `__ks.window.isFullscreen` | Check if window is fullscreen |
| `__ks.window.setAlwaysOnTop` | Set always-on-top state |
| `__ks.window.setResizable` | Set resizable state |
| `__ks.window.setDecorations` | Set window decorations (title bar) |
| `__ks.window.center` | Center the window on screen |
| `__ks.window.beforeClose` | Register a close handler (return `{ cancel: true }` to prevent close) |

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

### `__ks.app.*`

| Command | Description |
|---|---|
| `__ks.app.getVersion` | Get app version |
| `__ks.app.getName` | Get app name |
| `__ks.app.getIdentifier` | Get app identifier |
| `__ks.app.exit` | Exit the application |
| `__ks.app.getConfig` | Get the app config (redacted) |

### `__ks.notification.*`

| Command | Description |
|---|---|
| `__ks.notification.post` | Post a desktop notification |
| `__ks.notification.cancel` | Cancel a notification |
| `__ks.notification.requestPermission` | Request notification permission |

### `__ks.fs.*`

| Command | Description |
|---|---|
| `__ks.fs.readTextFile` | Read a text file |
| `__ks.fs.writeTextFile` | Write a text file |
| `__ks.fs.readBinaryFile` | Read a binary file |
| `__ks.fs.writeBinaryFile` | Write a binary file |
| `__ks.fs.readDir` | List directory contents |
| `__ks.fs.createDir` | Create a directory |
| `__ks.fs.removeDir` | Remove a directory |
| `__ks.fs.removeFile` | Remove a file |
| `__ks.fs.rename` | Rename a file or directory |
| `__ks.fs.exists` | Check if a path exists |
| `__ks.fs.stat` | Get file metadata |

### `__ks.http.fetch`

| Command | Description |
|---|---|
| `__ks.http.fetch` | Make an HTTP request (method, url, headers, body) |

### `__ks.environment.*`

| Command | Description |
|---|---|
| `__ks.environment.getOS` | Get the OS type |
| `__ks.environment.getArch` | Get the CPU architecture |
| `__ks.environment.getLocale` | Get the system locale |

### `__ks.autostart.*`

| Command | Description |
|---|---|
| `__ks.autostart.isEnabled` | Check if autostart is enabled |
| `__ks.autostart.enable` | Enable autostart |
| `__ks.autostart.disable` | Disable autostart |

### `__ks.deepLink.*`

| Command | Description |
|---|---|
| `__ks.deepLink.openURL` | Event emitted when a deep link URL is received |

## Events

The host emits the following events to the JS frontend:

| Event | Payload | Description |
|---|---|---|
| `menu` | `{ command, itemID }` | Native menu item clicked |
| `__ks.deepLink.openURL` | `{ url }` | Deep link URL received |
| `__ks.file.drop` | `{ paths: string[] }` | Files dropped onto window |
| `__ks.webview.downloadStarting` | `{ url, mimeType }` | Download initiated |
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
- **Allowlist**: Only commands in `security.commandAllowlist` are dispatchable.
- **XSS protection**: JSON strings are escaped for `</script>` and Unicode line/paragraph separators.
