# Kalsae Architecture

## Overview

Kalsae is a Swift-native, cross-platform desktop framework for shipping web UIs as small, secure native apps. The architecture follows a layered design:

```
┌─────────────────────────────────────────────────────┐
│                   KSApp (Public API)                 │
│  boot() · run() · quit() · emit() · postJob()       │
├─────────────────────────────────────────────────────┤
│              KalsaeCore (Platform-Agnostic)          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │  Config  │ │   IPC    │ │  Assets  │ │  PAL   │ │
│  │  Loader  │ │  Bridge  │ │  Cache   │ │Contracts│ │
│  └──────────┘ └──────────┘ └──────────┘ └────────┘ │
├─────────────────────────────────────────────────────┤
│              Platform Abstraction Layer              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │ Windows  │ │   macOS  │ │  Linux   │ │ iOS/An │ │
│  │  PAL     │ │   PAL    │ │   PAL    │ │ droid  │ │
│  └──────────┘ └──────────┘ └──────────┘ └────────┘ │
├─────────────────────────────────────────────────────┤
│              Native WebView Engine                    │
│  WebView2 · WKWebView · WebKitGTK · Android WebView  │
└─────────────────────────────────────────────────────┘
```

## Module Dependency Graph

```
Kalsae (public façade)
  ├── KalsaeCore (IPC, Config, Assets, Errors, PAL contracts)
  ├── KalsaePlatformWindows (Win32 + WebView2)
  ├── KalsaePlatformMac (AppKit + WKWebView)
  ├── KalsaePlatformLinux (GTK4 + WebKitGTK)
  ├── KalsaePlatformIOS (UIKit + WKWebView)
  └── KalsaePlatformAndroid (JNI + Android WebView)

KalsaeCLI (tooling)
  ├── KalsaeCLICore (Packager, BindingsGenerator, ProjectTemplate, Shell)
  └── KalsaeCore (Config loading)

KalsaeMacros (consumer-side @KSCommand entry points)
  └── KalsaeMacrosPlugin (SwiftSyntax macro implementation)

CKalsaeWV2 (C++ shim for WebView2, Windows-only)
CKalsaeGtk (C shim for GTK4, Linux-only)
CGtk4, CWebKitGTK (systemLibrary modulemaps, Linux pkg-config)
```

## Boot Sequence

`KSApp.boot()` is a thin coordinator that delegates the platform-agnostic
decisions to `KSBootOrchestrator` (in `KalsaeCore`). The platform host itself
is created by `KSDemoHostFactory.makeHost(...)` which returns `any KSDemoHost`
selected at compile time via `#if os(...)`.

1. **Config Loading** — `KSConfigLoader.load(from:)` reads `Kalsae.json` and validates the schema. In debug builds, `KALSAE_CONFIG` / `--kalsae-config` may override the path; release builds ignore the override.
2. **Window Selection** — `KSBootOrchestrator.selectWindow(from:label:)` picks the target window config.
3. **Command Registry** — `KSCommandRegistry` is created; `commandAllowlist` / `commandAllowlistAll` and `commandRateLimit` are applied **before** user registration. Built-in `__ks.*` commands use `registerInternal()` and bypass the allowlist (governed by their dedicated scopes instead).
4. **User Registration** — The `configure` closure runs, registering `@KSCommand` handlers.
5. **Platform Host** — `KSDemoHostFactory.makeHost(...)` returns an `any KSDemoHost` (e.g. `KSWindowsDemoHost`, `KSMacDemoHost`, `KSLinuxDemoHost`, `KSiOSDemoHost`, `KSAndroidDemoHost`).
6. **Serving Mode** — `KSBootOrchestrator.decideServingMode()` chooses how frontend assets are served:
   - `.virtualHost(root)` — local files served via `https://app.kalsae/` (Windows) or `ks://app/` (others)
   - `.devServer` — direct connection to a live dev server
   - `.fallback` — raw URL passthrough
7. **Security Setup** — CSP injection script, context menu policy, external drop policy, navigation/download/popup gates applied.
8. **Builtin Commands** — `__ks.window.*`, `__ks.shell.*`, `__ks.clipboard.*`, `__ks.app.*`, `__ks.dialog.*`, `__ks.fs.*`, `__ks.http.fetch`, `__ks.notification.*`, `__ks.autostart.*`, `__ks.deepLink.*` registered.
9. **Deep Link & Autostart** — Optional backends initialized from config.
10. **Menu/Tray Subscription** — Native menu/tray clicks routed to JS events and command dispatch.

`KS{Mac,Linux,iOS,Windows,Android}Platform.runOnMain()` carries only the
platform-specific message-loop / lifecycle work; the boot decisions above live
in `KSBootOrchestrator` (single source of truth).

## IPC Architecture

```
JS (WebView)                    Swift (Host)
┌──────────┐                  ┌──────────────────┐
│ invoke() │ ──JSON──▶        │ KSIPCBridgeCore  │
│ emit()   │                  │  ┌────────────┐  │
│ listen() │ ◀──JSON────      │  │ KSCommand  │  │
└──────────┘                  │  │ Registry   │  │
                              │  └────────────┘  │
                              └──────────────────┘
```

- **Wire format**: `KSIPCMessage` with `kind` (invoke/response/event), `id`, `name`, `payload`, `isError`.
- **Inbound frame limit**: 16 MB (`KSIPCBridgeCore.maxFrameBytes`).
- **Rate limiting**: Token-bucket algorithm (`KSCommandRateLimit`), configurable per-app.
- **Allowlist**: `commandAllowlist` in `KSSecurityConfig` restricts which user commands JS can invoke (`nil`/`[]` = deny-all since 0.4.0; built-in `__ks.*` commands always bypass).
- **Threading**: `Task.detached` for dispatch, `MainHop` closure for UI-thread response posting.

## Security Model

| Layer | Mechanism |
|---|---|
| **CSP** | Default: `default-src 'self'; script-src 'self'; ...` — injected as both HTTP header (Windows) and meta tag (all platforms) |
| **Command Allowlist** | Only explicitly listed user `@KSCommand` names are dispatchable from JS. `nil`/`[]` = deny-all (default since 0.4.0). Built-in `__ks.*` commands bypass and are governed by their own scopes. |
| **Filesystem** | `KSFSScope` with allow/deny glob patterns, `$APP`/`$HOME`/`$DOCS`/`$TEMP` placeholders |
| **Shell** | `KSShellScope` — `openExternalSchemes`, `showItemInFolder`, `moveToTrash` independently controlled |
| **HTTP Fetch** | `KSHTTPScope` — origin allowlist for `__ks.http.fetch` |
| **Notifications** | `KSNotificationScope` — `post`, `cancel`, `requestPermission` independently controlled |
| **Navigation** | `KSNavigationScope` — top-level navigation allowlist |
| **Downloads** | `KSDownloadScope` — enable/disable WebView downloads |
| **Context Menu** | `ContextMenuPolicy` — `.default` or `.disabled` |
| **External Drop** | `allowExternalDrop` — when disabled, OS file drops become `__ks.file.drop` events |
| **Rate Limiting** | Token-bucket per second, configurable burst |
| **Frame Size** | 16 MB max inbound IPC frame |

## Platform Abstraction Layer (PAL)

Each platform implements the `KSPlatform` protocol, which exposes:

- `windows` — `KSWindowBackend`
- `menus` — `KSMenuBackend`
- `tray` — `KSTrayBackend`
- `dialogs` — `KSDialogBackend`
- `notifications` — `KSNotificationBackend`
- `clipboard` — `KSClipboardBackend`
- `shell` — `KSShellBackend`
- `accelerators` — `KSAcceleratorBackend`
- `autostart` — `KSAutostartBackend`
- `deepLink` — `KSDeepLinkBackend`

### Platform Status

| Platform | Status | Notes |
|---|---|---|
| Windows | ✅ Stable | Full PAL, WebView2, WinRT notifications, Registry autostart, WM_COPYDATA single instance |
| macOS | ✅ Stable | Full PAL, WKWebView, UserNotifications, SMAppService autostart, NSRunningApp single instance |
| Linux | ✅ Stable | Full PAL, WebKitGTK 6.0, D-Bus SNI tray, Unix socket single instance |
| iOS | 🔶 Preview | PAL implemented, `run()` path available; security handlers wired in `runOnMain()` |
| Android | ✅ Stable | Full PAL via JNI bridge: dialogs, context menus via `PopupMenu` routed through `KSAndroidCommandRouter`, notifications, clipboard, deep link. `installAppMenu`/`installWindowMenu` are intentional no-ops (no persistent menubar in single-Activity model). `run()` is permanently unsupported (JVM Activity-controlled lifecycle) — use `KSApp.boot()` + `KSAndroidDemoHost` from a Kotlin host |

## Key Design Decisions

1. **No bundled Chromium/Node** — Reuses the OS web engine, keeping apps small (~5 MB).
2. **Typed throws** — All async functions use `throws(KSError)` for predictable error handling.
3. **Actor-based registry** — `KSCommandRegistry` is an `actor` for thread-safe command dispatch.
4. **NSLock over ad-hoc locks** — When `final class @unchecked Sendable` is needed, `NSLock` is preferred.
5. **Virtual host serving** — Local assets served via `https://app.kalsae/` (Windows) or `ks://app/` (others) enables proper CSP headers.
6. **`#if os()` gating** — Platform-specific code is conditionally compiled, never conditionally linked at runtime.

## Window Visual Options

### Transparent / layered windows (Windows only, v0.3+)

`KSWindowConfig.transparent: Bool` enables a translucent host window so the
WebView2 controller's alpha channel composites against the desktop or Mica
background instead of an opaque solid fill.

**Windows pipeline** (`KalsaePlatformWindows`):

1. `Win32Window.init` adds `WS_EX_LAYERED` to `exStyle` before
   `CreateWindowExW`.
2. After creation, `SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)` is
   called once. The window-level alpha is left at 255 (opaque); actual
   transparency is delegated to the WebView2 controller's
   `DefaultBackgroundColor`.
3. `WM_ERASEBKGND` returns `1` without painting so DWM can blend the desktop
   behind the WebView.
4. `KSWindowsDemoHost.applyVisualOptions` automatically calls
   `setDefaultBackgroundColor(KSColorRGBA(0,0,0,0))` whenever
   `windowConfig.transparent` is `true` (or `webview.transparent` is set).
5. The web content itself must avoid opaque backgrounds
   (`html, body { background: transparent; }`).

**Interaction with `backgroundColor`**: an explicit, fully-opaque
`backgroundColor` cancels the transparency effect. Document this in the host
config when both fields are used.

**Interaction with `KSWebViewOptions.backdropType`**: Mica / Acrylic /
Tabbed backdrops require a transparent host window to be visible. When
`backdropType` is one of those three and `transparent` is left at `false`,
`KSWindowsDemoHost.init` auto-promotes `transparent` to `true` and emits a
one-time warning. Set `transparent: true` explicitly in the config to
silence the warning. `backdropType: auto` and `none` do not trigger the
promotion since they have no visual effect.

**Other platforms (macOS / Linux / iOS / Android)**: not implemented.
Setting `transparent: true` logs a one-time warning at host construction
time and is otherwise ignored.
