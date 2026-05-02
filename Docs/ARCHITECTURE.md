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

1. **Config Loading** — `KSConfigLoader.load(from:)` reads `Kalsae.json` and validates the schema.
2. **Window Selection** — `selectWindow(from:label:)` picks the target window config.
3. **Command Registry** — `KSCommandRegistry` is created; `commandAllowlist` is applied before user registration.
4. **User Registration** — The `configure` closure runs, registering `@KSCommand` handlers.
5. **Platform Host** — Platform-specific `DemoHost` is created (e.g. `KSWindowsDemoHost`).
6. **Serving Mode** — `decideServingMode()` determines how frontend assets are served:
   - `.virtualHost(root)` — local files served via `https://app.kalsae/` (Windows) or `ks://app/` (others)
   - `.devServer` — direct connection to a live dev server
   - `.fallback` — raw URL passthrough
7. **Security Setup** — CSP injection script, context menu policy, external drop policy applied.
8. **Builtin Commands** — `__ks.window.*`, `__ks.shell.*`, `__ks.clipboard.*`, `__ks.app.*`, etc. registered.
9. **Deep Link & Autostart** — Optional backends initialized from config.
10. **Menu/Tray Subscription** — Native menu/tray clicks routed to JS events and command dispatch.

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
- **Allowlist**: `commandAllowlist` in `KSSecurityConfig` restricts which commands JS can invoke.
- **Threading**: `Task.detached` for dispatch, `MainHop` closure for UI-thread response posting.

## Security Model

| Layer | Mechanism |
|---|---|
| **CSP** | Default: `default-src 'self'; script-src 'self'; ...` — injected as both HTTP header (Windows) and meta tag (all platforms) |
| **Command Allowlist** | Only explicitly listed `@KSCommand` names are dispatchable from JS |
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
| Linux | 🔶 Preview | Full PAL, WebKitGTK 6.0, D-Bus SNI tray, Unix socket single instance |
| iOS | 🔶 Preview | PAL implemented, `run()` throws `unsupportedPlatform` |
| Android | 🔶 Preview | PAL implemented, `run()` throws `unsupportedPlatform` (JVM Activity-controlled lifecycle) |

## Key Design Decisions

1. **No bundled Chromium/Node** — Reuses the OS web engine, keeping apps small (~5 MB).
2. **Typed throws** — All async functions use `throws(KSError)` for predictable error handling.
3. **Actor-based registry** — `KSCommandRegistry` is an `actor` for thread-safe command dispatch.
4. **NSLock over ad-hoc locks** — When `final class @unchecked Sendable` is needed, `NSLock` is preferred.
5. **Virtual host serving** — Local assets served via `https://app.kalsae/` (Windows) or `ks://app/` (others) enables proper CSP headers.
6. **`#if os()` gating** — Platform-specific code is conditionally compiled, never conditionally linked at runtime.
