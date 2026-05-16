# AGENTS.md

Guidance for AI coding assistants (GitHub Copilot, Claude, Cursor, Aider, Codex,
etc.) working on this repository. **Read this file before making changes.**

> 한글 핵심 요약은 각 섹션 끝의 _🇰🇷_ 줄을 참고하세요.

---

## 1. Project at a Glance

**Kalsae** is a Swift-native, cross-platform desktop framework for shipping web
UIs as small, secure native apps (similar in spirit to Tauri/Electron, but the
host is pure Swift 6 and the WebView is the OS engine).

- Language: **Swift 6.0** (`swift-tools-version:6.0`, language mode v6)
- Build system: **SwiftPM** (single workspace, no Xcode project)
- Tests: **swift-testing** (`@Test`, `@Suite`, `#expect`, `Issue.record`) — **not** XCTest
- Platforms: **Windows** (stable) · **macOS** (stable) · **Linux** (stable) · **iOS** (stable) · **Android** (stable)
- WebView engines: WebView2 (Win) · WKWebView (mac, iOS) · WebKitGTK 6.0 (Linux) · Android WebView (Android)

_🇰🇷 Swift 6.0 + SPM + swift-testing. Windows/macOS가 가장 완성도 높음._

---

## 2. Build & Test (most-used commands)

```bash
# Build everything (clean ~50s)
swift build

# Build the demo executable only
swift build --product kalsae-demo

# Run the full test suite
swift test

# Filter to a single test or suite
swift test --filter "name"

# Run sequentially (use when packager / temp-dir tests get flaky)
swift test --no-parallel
```

**Platform prerequisites:**

| OS | Required setup |
|---|---|
| Windows 10 1809+ | Visual Studio Build Tools (MSVC 14+); `kalsae build` fetches the WebView2 SDK automatically. For bare `swift build`, run `./Scripts/fetch-webview2.ps1` once to populate `Vendor/WebView2/`, then `./Scripts/stage-webview2-loader.ps1` after every build to copy `WebView2Loader.dll` next to the produced executable (otherwise `LoadLibraryW` fails with `0x8007007E`) |
| macOS 14+ | none |
| Linux | `apt install libgtk-4-dev libwebkitgtk-6.0-dev libsoup-3.0-dev libsecret-1-dev` |
| iOS | Xcode 15+ (Swift 6 toolchain) |
| Android | Android Studio + NDK r27+ + Gradle 8+ (build & run); CI/native cross-compile additionally needs **Swift Android SDK 6.2** (Linux/macOS hosts only — Windows hosts must use WSL). See `Scripts/cross-compile-android.sh`. |

**Shell rules (Windows):**

- This repo is developed in **PowerShell 5.1 / 7**. Chain commands with `;` —
  **never** `&&`.
- Working directory is the repository root (this workspace).

_🇰🇷 `swift build` / `swift test`. `kalsae build`는 WebView2를 자동 fetch함. bare `swift build` 사용 시만 `./Scripts/fetch-webview2.ps1` 먼저 실행._
_🇰🇷 PowerShell 체이닝은 `;`만 사용 (`&&` 금지)._

---

## 3. Repository Layout

```text
Sources/
  Kalsae/                  Public façade module (KSApp, KSApp+Boot, …)
  KalsaeCore/              IPC, Config, Assets, Errors, Logging, PAL contracts
  KalsaeMacros/            @KSCommand macro entry points (consumer side)
  KalsaeMacrosPlugin/      SwiftSyntax-based macro implementation
  KalsaeCLI/               `kalsae` executable (new/dev/build/generate)
  KalsaeCLI/Support/       BindingsGenerator, Packager, ProjectTemplate, Shell
                           (compiled as an internal `KalsaeCLICore` target)
  KalsaeDemo/              Runnable demo app (kalsae-demo executable)

  KalsaePlatformWindows/   Win32 + WebView2 PAL
  KalsaePlatformMac/       AppKit + WKWebView PAL (stable)
  KalsaePlatformLinux/     GTK4 + WebKitGTK PAL (stable)
  KalsaePlatformIOS/       UIKit + WKWebView PAL (stable)
  KalsaePlatformAndroid/   JNI + Android WebView PAL (stable)

  CKalsaeWV2/              C++ shim for WebView2 (Windows-only)
  CKalsaeGtk/              C shim for GTK4 (Linux-only)
  CGtk4/, CWebKitGTK/      systemLibrary modulemaps (Linux pkg-config)

Tests/
  KalsaeCLITests/          Packager, BindingsGenerator, ProjectTemplate
  KalsaeCoreTests/         AssetCache/Resolver, IPC, Config, PAL contract tests
  KalsaeMacrosTests/       Macro expansion + diagnostics (uses
                           SwiftSyntaxMacrosTestSupport)
  KalsaePlatformWindowsTests/  Windows PAL integration tests
  KalsaePlatformMacTests/      macOS PAL integration tests
  KalsaePlatformLinuxTests/    Linux PAL integration tests
  KalsaePlatformIOSTests/      iOS PAL integration tests
  KalsaePlatformAndroidTests/  Android PAL integration tests

Samples/
  KalsaeAndroidSample/     Android sample project (Gradle build)

Scripts/
  fetch-webview2.ps1       Downloads WebView2 NuGet → Vendor/WebView2/
  cross-compile-android.sh Cross-compile + APK assemble (Linux/macOS only)

.github/workflows/
  ci.yml                   Main CI (Windows + macOS + Linux builds & tests, Swift 6.3.1 on Windows via compnerd/gha-setup-swift)
  android-packager.yml     PackagerAndroid unit tests (host-OS-agnostic emit)
  phase-android-e2e.yml    Android E2E: cross-compile + Gradle APK (Ubuntu, Swift 6.2)
  store-windows-msix.yml   Store distribution: Windows MSIX
  store-macos-mas.yml      Store distribution: Mac App Store
  store-macos-devid.yml    Store distribution: macOS Developer ID notarization
  store-ios-appstore.yml   Store distribution: iOS App Store
```

_🇰🇷 Sources/Kalsae* = Swift, Sources/CKalsae* = C/C++ 브리지(플랫폼 전용)._
_🇰🇷 iOS/Android PAL 및 테스트 타겟이 추가됨._

---

## 4. Coding Conventions

### Swift style

- File and type prefix: **`KS`** (e.g. `KSApp`, `KSError`, `KSAssetCache`).
- File name matches the primary type: `KSFoo.swift` defines `KSFoo`.
- Korean comments are fine. Doc comments (`///`) on **public** API are required.
- Prefer `struct` / `actor` over `class`. When a `final class @unchecked
  Sendable` is justified (e.g. `KSCommandRegistry`, `KSAssetCache`), use
  `NSLock` rather than ad-hoc locks.

### Concurrency

- **Typed throws everywhere:** `func ...() async throws(KSError) -> T`.
- Prefer bare `catch` (it auto-binds to `KSError` when the do block is typed).
  Two legitimate exceptions where you keep `catch let e as KSError`:
  1. **Closure contexts** (e.g. `MainActor.run { … }`, anonymous closures):
     the closure type erases the typed throw, so use the cast pattern
     `catch { return .failure(error as? KSError ?? KSError(code: .internal, …)) }`.
  2. **Mixed throw sites** in one `do` block (e.g. JSONEncoder + a user
     handler): keep `catch let e as KSError { … } catch { … wrap … }`.
- No force unwraps (`!`) or force tries (`try!`) in non-test code.

### SwiftPM specifics

- `swiftLanguageMode(.v6)` and `InternalImportsByDefault` are enabled
  package-wide via `commonSwiftSettings`.
- Files that expose **public** types **must** use `public import Foundation`
  (etc.) — `internal import` on those modules will fail to compile.
- Resources copied with `.copy("Templates")` retain directory structure.
  Access them via `Bundle.module.url(forResource:withExtension:subdirectory:)`.

### Platform gating

- Use `.when(platforms: [.windows])` etc. in `Package.swift` linker/cxx flags.
- Use `#if os(Windows)` / `os(macOS)` / `os(Linux)` / `os(iOS)` / `os(Android)` in source files.

_🇰🇷 typed throws + bare catch 우선. 액터 대안은 NSLock. public 노출 파일은_
_`public import` 필수. 리소스는 `Bundle.module.url(..., subdirectory:)`._

---

## 5. Platform Notes

### Windows

- WebView2 SDK lives at `Vendor/WebView2/` (gitignored after fetch).
- C++ shim (`Sources/CKalsaeWV2/`) is built with:
  - `UNICODE`, `_UNICODE`, `_WIN32_WINNT=0x0A00`
  - Static link: `WebView2LoaderStatic`, plus `ole32`, `runtimeobject`, etc.
- Memory passed across the C boundary uses `KSWV2_Alloc` / `KSWV2_Free` so the
  CRT matches on both sides — see [kswv2_resource.cpp](Sources/CKalsaeWV2/src/kswv2_resource.cpp).
- Full PAL: windows, menus, tray, dialogs, notifications (WinRT), clipboard,
  shell, accelerators, autostart (Registry), deep link (Registry), single
  instance (WM_COPYDATA), window state persistence.

### macOS

- Deployment target is `macOS 14`.
- Full PAL: windows, menus, tray, dialogs, notifications (UserNotifications),
  clipboard, shell, accelerators, autostart (SMAppService), deep link (Launch
  Services), single instance (NSRunningApp), window state persistence.
- Security: `setDefaultContextMenusEnabled` / `setAllowExternalDrop` apply via
  WKUserScript (preventDefault on `contextmenu` / `dragover` / `drop`).
  `installSecurityHandlers(allowPopups:openExternal:)` installs a WKUIDelegate
  (popup blocking + media-capture deny) and WKNavigationDelegate (external URL
  routing) — wired in `runOnMain()` (see [Docs/SECURITY.md](Docs/SECURITY.md)).
- **Known gaps:** `installFileDropEmitter` is a best-effort warning stub;
  proper external file-drop forwarding requires NSWindow draggingDestination
  integration (deferred).

### Linux

- Requires GTK4 + WebKitGTK 6.0 via pkg-config.
- Full PAL: windows, menus, dialogs, notifications (notify-send), clipboard,
  shell, autostart (XDG .desktop), deep link (XDG MIME), single instance (Unix
  socket), window-scoped accelerators (`GtkShortcutController`, LOCAL scope),
  window state persistence (size/maximized/fullscreen always; position on X11
  only — Wayland compositors control placement), system tray (D-Bus
  StatusNotifierItem + DBusMenu, no AppIndicator3/libayatana dependency — works
  on KDE/Cinnamon/XFCE/Pantheon and GNOME with AppIndicator extension; vanilla
  GNOME falls back to no-op with a warning).
- Virtual host serves `ks://app/` only (`https://app.kalsae/` is Windows-only —
  WebKitGTK cannot intercept `http(s)`); responses include CSP +
  `X-Content-Type-Options: nosniff` + `Referrer-Policy: no-referrer`.
- Security: WebKit signal handlers in CKalsaeGtk enforce `contextMenu`,
  `allowExternalDrop`, and `allowPopups` (via `decide-policy` for new-window
  actions, with external URL routing) — wired in `runOnMain()` (see [Docs/SECURITY.md](Docs/SECURITY.md)).
  Menu/tray clicks route through `KSLinuxCommandRouter` to JS + commandRegistry;
  `appMenu` / `windowMenu` install in `runOnMain()`.
- **Stubs (planned):** system-wide global hot-keys (deferred — no standard
  Wayland protocol), `installFileDropEmitter` (WebKitGTK does not expose external drop interception).

### iOS

- Deployment target: iOS 16 (via `Package.swift`).
- PAL surfaces: windows, dialogs (UIDocumentPicker / UIAlertController defaults
  installed by the backend itself), menus (context-only via UIAlertController
  actionSheet — `installAppMenu` / `installWindowMenu` are intentional no-ops
  with a once-only warning, mirroring Android's single-Activity model),
  notifications (UNNotification), shell, clipboard, deep link. Menu selections
  route through `KSiOSCommandRouter.shared` (mirrors
  `KSMacCommandRouter` / `KSWindowsCommandRouter` / `KSLinuxCommandRouter` /
  `KSAndroidCommandRouter`).
- **Permanently unsupported:** `KSiOSPlatform.run()` always throws
  `unsupportedPlatform` by design — iOS lifecycle is UIApplication-controlled.
  Use `KSApp.boot()` + `KSiOSDemoHost` from a UIKit `@main` entry point instead.
- WebView bridge: `WKWebView` + `WKUserContentController` message handler.
  Devtools-off-by-default (`isInspectable = false` on iOS 16.4+).
- Security: same WKUserScript + WKUIDelegate / WKNavigationDelegate pattern as
  macOS (see [Docs/SECURITY.md](Docs/SECURITY.md)); `ks://` responses include
  `X-Content-Type-Options: nosniff` + `Referrer-Policy: no-referrer` (parity
  with macOS / Linux). `installFileDropEmitter` is a stub (UIDropInteraction
  integration deferred).
- **Packaging:** `kalsae build --ios --ios-executable <path>` emits a minimal
  `.app` bundle (Info.plist with `NSAllowsArbitraryLoads=false`, sanitized
  `Kalsae.json`, frontend at root) under `dist/ios-<App>-<ver>/`. Host OS
  is irrelevant — emission is pure Swift string output. Actual install
  requires macOS + Xcode (`xcrun simctl install booted <bundle>`). Source:
  [PackagerIOS.swift](Sources/KalsaeCLI/Support/PackagerIOS.swift).

### Android

- Minimum API level: 26 (Android 8 Oreo). Target API level: 35 (Android 15).
- Cross-compile target: `aarch64-unknown-linux-android26` (or
  `x86_64-linux-android26` for emulator).
- JNI entry points in `Sources/KalsaePlatformAndroid/JNI/`.
- PAL surfaces: windows, dialogs, menus (context-only via `PopupMenu`),
  notifications (JNI bridge), shell, clipboard, deep link (JNI). Menu
  selections route through `KSAndroidCommandRouter.shared` (mirrors
  `KSMacCommandRouter` / `KSWindowsCommandRouter` / `KSLinuxCommandRouter`).
  `installAppMenu` / `installWindowMenu` are intentional no-ops — Android's
  single-Activity model has no persistent menubar.
- **Permanently unsupported:** `KSAndroidPlatform.run()` always throws `unsupportedPlatform`
  by design — Android lifecycle is JVM/Activity-controlled. Use `KSApp.boot()` +
  `KSAndroidDemoHost` with Kotlin host instead.
- **Packaging:** `kalsae build --android --android-native-lib <libKalsaePlatformAndroid.so>`
  emits a complete Gradle project (root + `app/` + Kotlin sources + manifest +
  5 mipmap densities + `jniLibs/arm64-v8a/`) under `dist/android-<App>-<ver>/`.
  The host OS is irrelevant — emission is pure Swift string output. After emit,
  run `gradle wrapper ; ./gradlew assembleRelease` (or import in Android Studio).
  Source: [PackagerAndroid.swift](Sources/KalsaeCLI/Support/PackagerAndroid.swift).
- Sample project: `Samples/KalsaeAndroidSample/` (Gradle build).

_🇰🇷 Windows = 풍 PAL. macOS = 풍 PAL (보안 핸들러 적용; 파일 드롭 emitter는 stub). Linux = 풍 PAL (보안/라우터/메뉴 적용; 파일 드롭 emitter stub). iOS = PAL + 보안 핸들러 적용. Android = 풍 PAL (라우터/컨텍스트 메뉴 포함; `run()`은 영구 미지원 — JVM Activity 모델). 세부 보안 동작은 [Docs/SECURITY.md](Docs/SECURITY.md) 참고._

---

## 6. CI Notes

- **Windows CI** (`ci.yml`) uses Swift **6.3.1-RELEASE** (matches local). Earlier 6.0
  releases hit a `ucrt`/`_visualc_intrinsics` cyclic-module bug on
  `windows-latest` MSVC headers — do not downgrade.
- Tests that touch the temp directory under high parallelism (Packager +
  resolver) can hit `ERROR_SHARING_VIOLATION (Win32 32)` from Defender /
  Search Indexer. Use `atomically: false` + small retry on Windows.
- Performance assertions (e.g. cache warm vs cold) **must** relax their
  threshold on CI:

  ```swift
  let isCI = ProcessInfo.processInfo.environment["CI"] != nil
  let multiplier: UInt64 = isCI ? 1 : 2
  #expect(warmNs * multiplier <= coldNs)
  ```

- Prefer `swift test --no-parallel` if you see flakes from temp-dir contention.
- **Android CI** is split across two workflows:
  - `android-packager.yml` runs `PackagerAndroid` unit tests on the same Swift
    matrix as the rest of the repo (currently Windows-only mirror). It uses a
    zero-byte stub `.so` so it does **not** build a real APK.
  - `phase-android-e2e.yml` runs on **Ubuntu** with **Swift 6.2** (the latest
    version with a matching Swift Android SDK release), installs the SDK via
    `swift sdk install`, cross-compiles `KalsaePlatformAndroid`, runs
    `kalsae build --android`, and assembles a real `app-debug.apk` via Gradle.
    The Swift version here intentionally diverges from Windows CI's 6.3.1
    because the Swift Android SDK does not yet ship for 6.3.x.
- iOS CI is not yet configured in `.github/workflows/`.

_🇰🇷 Windows CI는 Swift 6.3.1 고정. Android E2E CI는 Ubuntu + Swift 6.2 (Swift Android SDK 가용 버전). 성능 단언은 `CI` 환경변수로 완화._

---

## 7. Don'ts (frequent AI mistakes)

These are the things that have caused real regressions in this repo:

- ❌ **Don't refactor unrelated code.** Touch only what the task requires.
- ❌ **Don't add docstrings, comments, or type annotations to code you didn't
  change.**
- ❌ **Don't create new markdown files** to summarize work or "document
  changes" unless explicitly asked.
- ❌ **Don't import `XCTest`.** This repo uses swift-testing. Use `@Test`,
  `@Suite`, `#expect`, `#require`, `Issue.record(...)`.
- ❌ **Don't chain shell commands with `&&`** in PowerShell. Use `;`.
- ❌ **Don't use `internal import`** in files that expose `public` types.
- ❌ **Don't add `force unwrap` (`!`) or `try!`** in production code.
- ❌ **Don't bypass safety**: no `--no-verify` git commits, no `git push
  --force`, no destructive `rm -rf` shortcuts without explicit approval.
- ❌ **Don't bundle Chromium / Node**. The whole point of the framework is
  reusing the OS web engine.
- ❌ **Don't change `Package.swift` platform minimums** without coordination —
  raising `macOS(.v14)` etc. is a breaking change.

_🇰🇷 무관한 리팩토링/문서 자동 생성/XCTest/`&&`/force unwrap 모두 금지._

---

## 8. Useful Entrypoints

- Demo app:                [Sources/KalsaeDemo/Demo.swift](Sources/KalsaeDemo/Demo.swift)
- App lifecycle / boot:    [Sources/Kalsae/KSApp+Boot.swift](Sources/Kalsae/KSApp+Boot.swift)
- App public API:          [Sources/Kalsae/KSApp.swift](Sources/Kalsae/KSApp.swift)
- Single instance:         [Sources/Kalsae/KSApp+SingleInstance.swift](Sources/Kalsae/KSApp+SingleInstance.swift)
- Native UI helpers:       [Sources/Kalsae/KSApp+UI.swift](Sources/Kalsae/KSApp+UI.swift)
- IPC + built-in commands: [Sources/KalsaeCore/IPC/](Sources/KalsaeCore/IPC/)
- Config schema:           [Sources/KalsaeCore/Config/](Sources/KalsaeCore/Config/)
- Sample config:           [Examples/kalsae.sample.json](Examples/kalsae.sample.json)
- Macro implementation:    [Sources/KalsaeMacrosPlugin/KSCommandMacro.swift](Sources/KalsaeMacrosPlugin/KSCommandMacro.swift)
- CLI commands:            [Sources/KalsaeCLI/Commands/](Sources/KalsaeCLI/Commands/)
- Windows PAL:             [Sources/KalsaePlatformWindows/](Sources/KalsaePlatformWindows/)
- macOS PAL:               [Sources/KalsaePlatformMac/](Sources/KalsaePlatformMac/)
- Linux PAL:               [Sources/KalsaePlatformLinux/](Sources/KalsaePlatformLinux/)
- iOS PAL:                 [Sources/KalsaePlatformIOS/](Sources/KalsaePlatformIOS/)
- Android PAL:             [Sources/KalsaePlatformAndroid/](Sources/KalsaePlatformAndroid/)
- Android sample:          [Samples/KalsaeAndroidSample/](Samples/KalsaeAndroidSample/)
- WebView2 C++ shim:       [Sources/CKalsaeWV2/src/](Sources/CKalsaeWV2/src/)
- GTK C shim:              [Sources/CKalsaeGtk/](Sources/CKalsaeGtk/)

When in doubt, grep for an existing `KS*` type that does something similar
and follow its shape rather than inventing a new pattern.

_🇰🇷 새 패턴 만들기 전에 기존 `KS*` 유형을 grep해서 모양을 따라가세요._

---

## 9. Third-Party Licenses

Kalsae 자체는 **MIT** ([LICENSE](LICENSE))로 배포된다. 그러나 OS 웹엔진·네이티브
시스템 라이브러리에 **동적 링크**해 동작하므로, 최종 배포물(MSIX / AppImage /
.app / .apk 등)에는 다음 제3자 컴포넌트의 라이선스 고지가 따라야 한다.

| 컴포넌트 | 플랫폼 | 라이선스 | 링크 방식 | 번들 여부 |
|---|---|---|---|---|
| WebView2 SDK | Windows | MS 독점 (재배포 SDK 라이선스) | 정적 (loader) + 동적 (WebView2Loader.dll) | 시스템 Edge 런타임 |
| WKWebView | macOS / iOS | Apple SDK | 시스템 프레임워크 | OS 내장 |
| WebKitGTK 6.0 | Linux | **LGPL-2.1** | 동적 (pkg-config) | ❌ 시스템 패키지 |
| GTK 4 / GLib | Linux | **LGPL-2.1** | 동적 (pkg-config) | ❌ 시스템 패키지 |
| libsoup-3.0 | Linux | **LGPL-2** | 동적 (pkg-config) | ❌ 시스템 패키지 |
| **libsecret-1** | Linux | **LGPL-2.1+** | 동적 (pkg-config) | ❌ 시스템 패키지 |
| Android WebView | Android | Apache-2.0 + LGPL (WebKit) | 시스템 컴포넌트 | OS 내장 |
| swift-argument-parser | 전체 | Apache-2.0 | 정적 (SwiftPM) | ✅ 바이너리 포함 |
| swift-log | 전체 | Apache-2.0 | 정적 (SwiftPM) | ✅ 바이너리 포함 |
| swift-syntax | 빌드 시 | Apache-2.0 | 매크로 플러그인 | 빌드 시만 |

**핵심 원칙 — LGPL 호환성을 유지하기 위해 반드시 지켜야 할 사항:**

1. **번들 금지** — WebKitGTK / GTK / libsoup / libsecret 등 LGPL 라이브러리는
   `.so`를 배포물 안에 복사하지 말 것. 항상 시스템 패키지 매니저 의존성으로
   선언한다 (`apt`, `dnf`, AppImage `apt-deps:` 등).
2. **동적 링크만** — `pkg-config --libs`가 생성하는 `-l<name>` 플래그를 변경
   금지. 정적 링크(`-static`, `-Wl,-Bstatic`) 절대 추가 금지.
3. **고지 번들** — 배포물에 [Docs/THIRD-PARTY-NOTICES.md](Docs/THIRD-PARTY-NOTICES.md)
   사본 또는 동일 내용의 NOTICE 파일을 동봉할 것. CLI Packager (`kalsae build`)는
   향후 이 파일을 자동 복사하도록 확장할 예정이다.

**상세 본문 — 라이선스 전문·원천 URL·재배포 가이드는
[Docs/THIRD-PARTY-NOTICES.md](Docs/THIRD-PARTY-NOTICES.md)** 참고.

_🇰🇷 Kalsae 본체는 MIT. WebKitGTK·GTK·libsoup·libsecret 등은 LGPL이므로 **반드시 동적 링크 + 시스템 패키지 의존**으로 사용하고, 배포물에 NOTICE를 동봉할 것. 정적 링크·`.so` 번들 금지._
