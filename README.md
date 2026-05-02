# Kalsae

> A Swift-native, cross-platform desktop framework for shipping web UIs as small, secure native apps.

![Swift](https://img.shields.io/badge/swift-6.0-orange.svg) ![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20iOS%20%7C%20Android-lightgrey.svg) ![Status](https://img.shields.io/badge/status-experimental-yellow.svg) ![Version](https://img.shields.io/badge/version-0.2.0-blue.svg)

Kalsae lets you build desktop (and mobile) applications by combining a **native OS shell written in Swift** with a **web frontend** of your choice (Vite, Next.js, plain HTML — anything that produces static assets). It is in the same family as Tauri and Electron, but the host process is pure Swift 6 and the runtime stays small by reusing the OS web engine: **WebView2** on Windows, **WKWebView** on macOS/iOS, **WebKitGTK 6.0** on Linux, and **Android WebView** on Android.

> ⚠️ **Experimental.** APIs may change. Windows and macOS are the most complete targets today; Linux is feature-complete with some platform limitations (for example global hot-keys on Wayland and tray behavior on vanilla GNOME); iOS and Android are preview targets.

<details>
<summary>🇰🇷 한국어로 보기</summary>

**Kalsae**는 **Swift로 작성된 네이티브 OS 셸**과 원하는 **웹 프론트엔드**(Vite, Next.js, 일반 HTML 등)를 결합해 데스크톱/모바일 앱을 만드는 프레임워크입니다. Tauri나 Electron과 같은 계열이지만, 호스트 프로세스는 순수 Swift 6이며 OS의 웹 엔진(Windows의 **WebView2**, macOS/iOS의 **WKWebView**, Linux의 **WebKitGTK 6.0**, Android의 **Android WebView**)을 그대로 재사용해 런타임 크기를 작게 유지합니다.

> ⚠️ **실험적 단계입니다.** API는 변경될 수 있으며, Windows와 macOS가 가장 완성도가 높습니다. Linux는 기능 구현이 거의 완료되었지만(예: Wayland 글로벌 단축키, 순수 GNOME 트레이 동작 등) 플랫폼 제약이 일부 남아 있습니다. iOS와 Android는 프리뷰 단계입니다.

</details>

---

## Why Kalsae

- **Swift-native host.** No Node.js, no Rust toolchain on the desktop side. The shell, IPC, and platform integrations are all Swift 6 with typed throws and macros.
- **Small runtime.** No bundled Chromium. On Windows, WebView2 is fetched from Microsoft and bundled at package time; on macOS/Linux/iOS the system web engine is used; on Android the system WebView is used.
- **Declarative configuration.** A single `Kalsae.json` describes windows, menus, tray, security, notifications, autostart, and deep links. No imperative bootstrap code required for most apps.
- **Type-safe IPC.** Expose Swift functions to JavaScript with the `@KSCommand` macro; arguments and return values are `Codable`. Optionally generate matching TypeScript types with `kalsae generate bindings`.

<details>
<summary>🇰🇷 한국어로 보기</summary>

- **Swift 네이티브 호스트** — 데스크톱 측에 Node.js나 Rust 툴체인이 필요 없습니다. 셸·IPC·플랫폼 통합 모두 Swift 6(typed throws, 매크로 활용)로 작성되었습니다.
- **작은 런타임** — Chromium을 번들링하지 않습니다. Windows에서는 패키징 시 Microsoft에서 WebView2를 받아 함께 배포하고, macOS/Linux/iOS/Android에서는 OS 내장 엔진을 그대로 사용합니다.
- **선언형 설정** — `Kalsae.json` 한 파일로 윈도우·메뉴·트레이·보안·알림·자동시작·딥링크를 정의합니다. 대부분의 앱은 별도의 부트스트랩 코드를 작성할 필요가 없습니다.
- **타입 안전 IPC** — `@KSCommand` 매크로로 Swift 함수를 JavaScript에 노출합니다. 인자와 반환값은 `Codable`이며, `kalsae generate bindings`로 TypeScript 타입을 자동 생성할 수 있습니다.

</details>

---

## Status

| Component | Stage | Notes |
|---|---|---|
| Core IPC, Config, Macros | Stable | Production-ready |
| **Windows** (Win32 + WebView2) | Stable | Full PAL (all features) |
| **macOS** (AppKit + WKWebView) | Stable | Full PAL (all features) |
| **Linux** (GTK4 + WebKitGTK 6.0) | Preview | Full PAL with platform caveats (global hot-keys on Wayland, tray behavior on vanilla GNOME) |
| **iOS** (UIKit + WKWebView) | Preview | PAL surfaces implemented; `run()` path available |
| **Android** (JNI + Android WebView) | Preview | PAL surfaces implemented; `run()` is permanently unsupported (Activity lifecycle) |

<details>
<summary>🇰🇷 한국어로 보기</summary>

| 구성요소 | 단계 | 비고 |
|---|---|---|
| 코어 IPC · 설정 · 매크로 | 안정 | 프로덕션 사용 가능 |
| **Windows** (Win32 + WebView2) | 안정 | 전체 PAL (모든 기능) |
| **macOS** (AppKit + WKWebView) | 안정 | 전체 PAL (모든 기능) |
| **Linux** (GTK4 + WebKitGTK 6.0) | 프리뷰 | 전체 PAL 구현, 플랫폼 제약 일부 존재 (Wayland 글로벌 단축키, 순수 GNOME 트레이) |
| **iOS** (UIKit + WKWebView) | 프리뷰 | PAL 구현됨; `run()` 경로 사용 가능 |
| **Android** (JNI + Android WebView) | 프리뷰 | PAL 구현됨; `run()`은 Activity 라이프사이클 특성상 영구 미지원 |

</details>

---

## Quick Start

### Prerequisites

- **Swift 6.0+** (typed throws, macros)
- **Windows 10 1809+** with Visual Studio Build Tools (MSVC for the C++ shim). `kalsae build` fetches the WebView2 SDK automatically on first use. For `swift build` directly, run [Scripts/fetch-webview2.ps1](Scripts/fetch-webview2.ps1) once to populate `Vendor/WebView2/`.
- **macOS** 14+ (no extra deps)
- **Linux**: `apt install libgtk-4-dev libwebkitgtk-6.0-dev libsoup-3.0-dev`
- **iOS**: Xcode 15+ (Swift 6 toolchain)
- **Android**: Android Studio, Android NDK 26+, Gradle 8+

On Windows PowerShell, chain commands with `;` (not `&&`).

### Build & Test

```bash
# Build everything
swift build

# Build demo executable only
swift build --product kalsae-demo

# Run full test suite
swift test

# Run a filtered test/suite
swift test --filter "name"

# Run sequentially (useful when temp-dir contention appears)
swift test --no-parallel
```

Tests in this repository use **swift-testing** (`@Test`, `@Suite`, `#expect`), not XCTest.

### Try the bundled demo

```bash
git clone <this-repo>
cd Kalsae
swift build
swift run kalsae-demo
```

### Scaffold a new app

```bash
# Vanilla (default) — no frontend build tooling
kalsae new MyDesktopApp

# With a frontend framework preset
kalsae new MyDesktopApp --frontend react
kalsae new MyDesktopApp --frontend react --package-manager pnpm
kalsae new MyDesktopApp --frontend vue  --package-manager yarn
# Supported presets: vanilla | react | vue | svelte
# Supported package managers: npm (default) | pnpm | yarn

cd MyDesktopApp
kalsae dev                     # run with hot iteration
kalsae build --package         # release build + WebView2 bundling
```

On Windows, `kalsae build` automatically runs `Scripts/fetch-webview2.ps1` when
the WebView2 SDK is missing (`--no-auto-fetch-web-view2` disables this).

### Add Kalsae as a SwiftPM dependency

If release tags are not available yet, use the `main` branch explicitly:

```swift
.package(url: "https://github.com/Kalsae/Kalsae.git", branch: "main")
```

When semver tags are published, prefer a version requirement:

```swift
.package(url: "https://github.com/Kalsae/Kalsae.git", from: "0.1.0")
```

<details>
<summary>🇰🇷 한국어로 보기</summary>

### 사전 요구사항

- **Swift 6.0 이상** (typed throws, 매크로)
- **Windows 10 1809 이상** + Visual Studio Build Tools (C++ shim용 MSVC). `kalsae build` 사용 시 WebView2 SDK를 자동으로 fetch합니다. `swift build`를 직접 사용하는 경우에는 [Scripts/fetch-webview2.ps1](Scripts/fetch-webview2.ps1)을 1회 실행해 `Vendor/WebView2/`를 준비하세요.
- **macOS** 14 이상 (추가 의존성 없음)
- **Linux**: `apt install libgtk-4-dev libwebkitgtk-6.0-dev libsoup-3.0-dev`
- **iOS**: Xcode 15+ (Swift 6 툴체인)
- **Android**: Android Studio, Android NDK 26+, Gradle 8+

Windows PowerShell에서는 명령 체이닝 시 `&&` 대신 `;`를 사용하세요.

### 빌드 & 테스트

```bash
# 전체 빌드
swift build

# 데모 실행 파일만 빌드
swift build --product kalsae-demo

# 전체 테스트
swift test

# 특정 테스트/스위트만 실행
swift test --filter "name"

# 순차 실행 (임시 디렉터리 경합 이슈 대응)
swift test --no-parallel
```

이 저장소의 테스트 프레임워크는 XCTest가 아니라 **swift-testing** (`@Test`, `@Suite`, `#expect`)입니다.

### 데모 실행

```bash
git clone <this-repo>
cd Kalsae
swift build
swift run kalsae-demo
```

### 새 프로젝트 만들기

```bash
# Vanilla (기본) — 별도 프론트엔드 빌드 도구 없음
kalsae new MyDesktopApp

# 프론트엔드 프레임워크 프리셋 지정
kalsae new MyDesktopApp --frontend react
kalsae new MyDesktopApp --frontend react --package-manager pnpm
kalsae new MyDesktopApp --frontend vue  --package-manager yarn
# 지원 프리셋: vanilla | react | vue | svelte
# 지원 패키지 매니저: npm (기본) | pnpm | yarn

cd MyDesktopApp
kalsae dev                     # 개발 모드 실행
kalsae build --package         # 릴리스 빌드 + WebView2 번들링
```

</details>

---

## Documentation

- [Architecture](Docs/ARCHITECTURE.md)
- [CLI Guide](Docs/CLI.md)
- [IPC Protocol](Docs/IPC.md)
- [Security Model](Docs/SECURITY.md)
- [Sample Config](Examples/kalsae.sample.json)

## Troubleshooting

### Windows: WebView2 loader not found during link

If you see `WebView2LoaderStatic.lib` link errors, ensure the SDK is installed in
your app project's own `Vendor/WebView2` directory:

```powershell
.\Scripts\fetch-webview2.ps1
```

If you run the script from a different checkout, target your app root explicitly:

```powershell
.\Scripts\fetch-webview2.ps1 -ProjectRoot C:\Path\To\YourApp
```

To verify resolved installation paths without downloading from NuGet:

```powershell
.\Scripts\fetch-webview2.ps1 -ProjectRoot C:\Path\To\YourApp -DryRun
```

You can also run the built-in smoke check:

```powershell
.\Scripts\smoke-fetch-webview2.ps1
```

### swift-syntax dependency cache looks broken

If SwiftPM repeatedly fails to resolve `swift-syntax` with a cache mismatch,
clear the local cache snapshot and resolve again:

```powershell
Remove-Item -Recurse -Force .build\repositories\swift-syntax-*
swift package resolve --disable-dependency-cache
```

<details>
<summary>🇰🇷 한국어로 보기</summary>

- [아키텍처](Docs/ARCHITECTURE.md)
- [CLI 가이드](Docs/CLI.md)
- [IPC 프로토콜](Docs/IPC.md)
- [보안 모델](Docs/SECURITY.md)
- [샘플 설정](Examples/kalsae.sample.json)

</details>

---

## Configuration at a Glance

A minimal `Kalsae.json`:

```json
{
  "app": {
    "name": "MyApp",
    "version": "0.1.0",
    "identifier": "dev.example.myapp"
  },
  "build": {
    "frontendDist": "dist",
    "devServerURL": "http://localhost:5173"
  },
  "windows": [
    { "label": "main", "title": "MyApp", "width": 1024, "height": 720 }
  ],
  "security": {
    "csp": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'",
    "commandAllowlist": null,
    "fs": { "allow": ["$DOCS/MyApp/**"], "deny": [] },
    "devtools": true
  }
}
```

Top-level sections: `app`, `build`, `windows[]`, `security`, optional `tray`, `menu`, `notifications`, `autostart`, `deepLink`. See [Examples/kalsae.sample.json](Examples/kalsae.sample.json) for a full reference and [Sources/KalsaeCore/Config/](Sources/KalsaeCore/Config/) for schema sources.

<details>
<summary>🇰🇷 한국어로 보기</summary>

최소한의 `Kalsae.json` 예시는 위와 같습니다. 최상위 섹션은 `app`, `build`, `windows[]`, `security`이며 선택적으로 `tray`, `menu`, `notifications`, `autostart`, `deepLink`를 지정할 수 있습니다. 전체 예시는 [Examples/kalsae.sample.json](Examples/kalsae.sample.json), 스키마 소스는 [Sources/KalsaeCore/Config/](Sources/KalsaeCore/Config/)를 참고하세요.

`security` 섹션은 다음 항목으로 앱을 보호합니다:

- `commandAllowlist` — JS에서 호출 가능한 명령 화이트리스트(`null`이면 등록된 모든 명령 허용)
- `fs.allow` / `fs.deny` — 파일시스템 접근 글롭 패턴 (`$APP`, `$HOME`, `$DOCS`, `$TEMP` 매크로 사용 가능)
- `csp` — Content-Security-Policy 헤더와 `<meta>` 태그로 주입
- `devtools` — DevTools 활성화 (릴리스 빌드는 강제로 `false`)
- `shell` — `openExternalSchemes`, `showItemInFolder`, `moveToTrash` 권한
- `notifications` — `post`, `cancel`, `requestPermission` 권한
- `http` — `__ks.http.fetch`의 허용 오리진/메서드/기본 헤더
- `downloads` — WebView 다운로드 허용 여부
- `navigation` — WebView 탐색 허용 목록
- `commandRateLimit` — IPC 명령 호출 속도 제한 (`rate`/`burst`)

</details>

---

## JavaScript API

Kalsae injects a runtime under `window.__KS_` exposing the following namespaces. All methods return `Promise`s.

| Namespace | Purpose | Example |
|---|---|---|
| `__KS_.invoke(cmd, args)` | Call a Swift `@KSCommand` or built-in command | `await __KS_.invoke("greet", { name: "Alice" })` |
| `__KS_.window` | Window state and geometry (24 methods) | `await __KS_.window.toggleMaximize()` |
| `__KS_.shell` | Open URLs, reveal files, trash files | `await __KS_.shell.openExternal("https://...")` |
| `__KS_.clipboard` | Read/write text, format check | `await __KS_.clipboard.writeText("hi")` |
| `__KS_.app` | Quit, environment info, hide/show | `await __KS_.app.environment()` |
| `__KS_.events` | `on` / `off` / `once` / `emit` | `__KS_.events.on("greet:done", cb)` |
| `__KS_.log` | Native logger (`trace`/`debug`/`info`/`warn`/`error`) | `__KS_.log.info("ready")` |
| `__KS_.dialog` | Native dialogs (message, open, save, folder) | `await __KS_.dialog.message({ type: "info", message: "Hello" })` |
| `__KS_.fs` | Filesystem operations (read/write/exists/list, etc.) | `await __KS_.fs.readTextFile({ path: "$DOCS/note.txt" })` |
| `__KS_.http` | HTTP fetch with security gating | `await __KS_.http.fetch({ url: "https://api.example.com" })` |
| `__KS_.autostart` | Launch-on-login control | `await __KS_.autostart.isEnabled()` |
| `__KS_.deepLink` | Custom URL scheme registration | `await __KS_.deepLink.register({ scheme: "myapp" })` |

### Drag region for frameless windows

```html
<div style="app-region: drag; height: 32px;">
  My App <button style="app-region: no-drag;">×</button>
</div>
```

### Errors

```js
try { await __KS_.invoke("doThing"); }
catch (e) {
  if (e instanceof window.KalsaeError) console.log(e.code, e.data);
}
```

<details>
<summary>🇰🇷 한국어로 보기</summary>

Kalsae는 페이지에 `window.__KS_` 런타임을 주입하며, 아래 네임스페이스를 제공합니다. 모든 메서드는 `Promise`를 반환합니다.

| 네임스페이스 | 용도 | 예시 |
|---|---|---|
| `__KS_.invoke(cmd, args)` | Swift `@KSCommand` 또는 내장 명령 호출 | `await __KS_.invoke("greet", { name: "Alice" })` |
| `__KS_.window` | 윈도우 상태/기하 (24개 메서드) | `await __KS_.window.toggleMaximize()` |
| `__KS_.shell` | URL 열기, 파일탐색기 열기, 휴지통 이동 | `await __KS_.shell.openExternal("https://...")` |
| `__KS_.clipboard` | 텍스트 읽기/쓰기, 형식 검사 | `await __KS_.clipboard.writeText("hi")` |
| `__KS_.app` | 종료, 환경 정보, 표시/숨김 | `await __KS_.app.environment()` |
| `__KS_.events` | `on` / `off` / `once` / `emit` | `__KS_.events.on("greet:done", cb)` |
| `__KS_.log` | 네이티브 로거 (`trace`/`debug`/`info`/`warn`/`error`) | `__KS_.log.info("ready")` |
| `__KS_.dialog` | 네이티브 다이얼로그 (메시지, 열기, 저장, 폴더) | `await __KS_.dialog.message({ type: "info", message: "Hello" })` |
| `__KS_.fs` | 파일시스템 작업 (읽기/쓰기/존재여부/목록 등) | `await __KS_.fs.readTextFile({ path: "$DOCS/note.txt" })` |
| `__KS_.http` | 보안 게이트가 적용된 HTTP fetch | `await __KS_.http.fetch({ url: "https://api.example.com" })` |
| `__KS_.autostart` | 로그인 시 자동 실행 제어 | `await __KS_.autostart.isEnabled()` |
| `__KS_.deepLink` | 커스텀 URL 스킴 등록 | `await __KS_.deepLink.register({ scheme: "myapp" })` |

프레임리스 윈도우의 드래그 영역은 CSS `app-region: drag | no-drag`로 지정합니다. 에러는 `window.KalsaeError`로 식별 가능하며 `code`와 `data` 필드를 가집니다.

</details>

---

## Swift SDK: `@KSCommand`

Annotate any Swift function and it becomes callable from JavaScript:

```swift
import Kalsae

struct GreetOut: Codable, Sendable { let message: String }

@KSCommand
func greet(name: String?) -> GreetOut {
    GreetOut(message: "Hello, \(name ?? "World")!")
}

@main
struct MyApp {
    static func main() async throws {
        let app = try await KSApp.boot(
            configURL: URL(fileURLWithPath: "Kalsae.json")
        ) { registry in
            await _ksRegister_greet(into: registry)
        }
        try await app.run()
    }
}
```

Supported signatures: any number of `Codable` parameters, `async`, `throws` (KSError preserved), `Encodable` returns, optional parameters with JSON-key omission.

See [Sources/KalsaeDemo/Demo.swift](Sources/KalsaeDemo/Demo.swift) for a complete, runnable example.

<details>
<summary>🇰🇷 한국어로 보기</summary>

Swift 함수에 `@KSCommand`만 붙이면 JavaScript에서 호출할 수 있는 명령이 됩니다. 매개변수는 개수 제한 없이 모두 `Codable`이면 되고, `async`/`throws`(`KSError`는 그대로 전달)/`Encodable` 반환을 지원합니다. Optional 매개변수는 JSON 키가 누락되어도 허용됩니다.

전체 예시는 [Sources/KalsaeDemo/Demo.swift](Sources/KalsaeDemo/Demo.swift)를 참고하세요.

</details>

---

## Built-in Commands

Available out of the box under the `__ks.` prefix — no registration needed.

| Domain | Count | Sample |
|---|---|---|
| `__ks.window.*` | 24 | `minimize`, `setSize`, `setTheme`, `setAlwaysOnTop`, `reload`, … |
| `__ks.shell.*` | 3 | `openExternal`, `showItemInFolder`, `moveToTrash` |
| `__ks.clipboard.*` | 4 | `readText`, `writeText`, `clear`, `hasFormat` |
| `__ks.notification.*` | 3 | `requestPermission`, `post`, `cancel` |
| `__ks.dialog.*` | 4 | `message`, `open`, `save`, `selectFolder` |
| `__ks.fs.*` | 11 | `readTextFile`, `readFile`, `writeTextFile`, `writeFile`, `exists`, `metadata`, `readDir`, `createDir`, `remove`, `rename`, `copyFile` |
| `__ks.http.fetch` | 1 | HTTP fetch with origin/method gating |
| `__ks.autostart.*` | 3 | `enable`, `disable`, `isEnabled` |
| `__ks.deepLink.*` | 4 | `register`, `unregister`, `isRegistered`, `currentLaunchURLs` |
| `__ks.app.*` + `__ks.environment` + `__ks.log` | 5 | `quit`, `environment`, `hide`, `show`, `log` |

Source: [Sources/KalsaeCore/IPC/](Sources/KalsaeCore/IPC/). All built-ins are gated by the `security` config — anything not allowed by `commandAllowlist`, `shell.*`, `notifications.*`, `fs`, `http`, `downloads`, or `navigation` returns `commandNotAllowed`.

<details>
<summary>🇰🇷 한국어로 보기</summary>

별도 등록 없이 `__ks.` 접두사로 즉시 사용 가능한 명령 목록입니다. 모든 내장 명령은 `security` 설정의 영향을 받으며, `commandAllowlist`/`shell.*`/`notifications.*`/`fs`/`http`/`downloads`/`navigation`에서 허용되지 않은 명령은 `commandNotAllowed` 에러를 반환합니다. 소스는 [Sources/KalsaeCore/IPC/](Sources/KalsaeCore/IPC/)에 있습니다.

</details>

---

## Platform Support Matrix

| Feature | Windows | macOS | Linux | iOS | Android |
|---|---|---|---|---|---|
| WebView load + IPC bridge | ✅ | ✅ | ✅ | ✅ | ✅ |
| Custom virtual host (`https://app.kalsae/` / `ks://app/`) | ✅ | 🔶¹ | 🔶¹ | 🔶¹ | 🔶¹ |
| DevTools | ✅ | ✅ | ✅ | ✅ | ✅ |
| Window create / close / show / hide | ✅ | ✅ | ✅ | ✅ | ✅ |
| Window minimize / maximize / fullscreen | ✅ | ✅ | ✅ | ✅ | ✅ |
| Window position / size / min-max bounds | ✅ | ✅ | ✅ | ✅ | ✅ |
| Theme (light / dark / system) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Zoom, capture preview, print UI | ✅ | ✅ | ✅ | ✅ | ✅ |
| Close interceptor (event-based close) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Multi-window | 🔶 | 🔶 | 🔶 | 🔶 | 🔶 |
| Native dialogs (message / open / save / folder) | ✅ | ✅ | ✅ | ✅ | 🔶 |
| Application & context menus | ✅ | ✅ | ✅ | ✅ | 🔶 |
| Keyboard accelerators (global hot-keys) | ✅ | ✅ | 🔶² | ❌ | ❌ |
| System tray icon + menu | ✅ | ✅ | 🔶⁴ | ❌ | ❌ |
| Native notifications | ✅ WinRT | ✅ UserNotifications | ✅ notify-send | ✅ UNNotification | ✅ JNI bridge |
| Shell (`openExternal` / `showItemInFolder` / `moveToTrash`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Clipboard (text + image + format check) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Autostart (launch on login) | ✅ Registry | ✅ SMAppService | ✅ XDG .desktop | ❌ | ❌ |
| Deep link / custom URL scheme | ✅ Registry | ✅ Launch Services | ✅ XDG MIME | ✅ | ✅ JNI |
| Single instance + argument forwarding | ✅ WM_COPYDATA | ✅ NSRunningApp | ✅ Unix socket | ❌ | ❌ |
| Filesystem (`__ks.fs.*`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| HTTP fetch (`__ks.http.fetch`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Window state persistence | ✅ | ✅ | ✅³ | ❌ | ❌ |

**Legend:** ✅ implemented · 🔶 partial · ❌ stub (planned)

¹ macOS / Linux / iOS / Android: only the `ks://app/` custom scheme is supported. The `https://app.kalsae/` form is Windows-only because of WebView engine limitations (WKURLSchemeHandler / WebKitGTK / WKWebView do not intercept `http(s)` schemes). Responses include `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, and `Referrer-Policy: no-referrer`.
² Linux: window-scoped accelerators only via `GtkShortcutController` (LOCAL scope). System-wide global hot-keys are out of scope for v1 due to a missing standard Wayland protocol.
³ Linux: size, maximized, and fullscreen are always restored. Window position is restored on X11 only — Wayland compositors control window placement and ignore programmatic positioning.
⁴ Linux: implemented via D-Bus StatusNotifierItem + DBusMenu (no AppIndicator3 / libayatana dependency). Works on KDE Plasma, Cinnamon, XFCE, Pantheon, and GNOME with the AppIndicator extension. Vanilla GNOME has no native SNI support — install logs a warning and falls back to no-op. Submenus are not supported in v1 (flat menus only).

<details>
<summary>🇰🇷 한국어로 보기</summary>

| 기능 | Windows | macOS | Linux | iOS | Android |
|---|---|---|---|---|---|
| WebView 로딩 + IPC 브리지 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 가상 호스트 (`https://app.kalsae/` / `ks://app/`) | ✅ | 🔶¹ | 🔶¹ | 🔶¹ | 🔶¹ |
| 개발자 도구 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 윈도우 생성/종료/표시/숨김 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 윈도우 최소/최대화/전체화면 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 윈도우 위치/크기/최소-최대 제한 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 테마 (라이트/다크/시스템) | ✅ | ✅ | ✅ | ✅ | ✅ |
| 줌, 화면 캡처, 프린트 UI | ✅ | ✅ | ✅ | ✅ | ✅ |
| 닫기 인터셉터 (이벤트 기반 닫기) | ✅ | ✅ | ✅ | ✅ | ✅ |
| 다중 윈도우 | 🔶 | 🔶 | 🔶 | 🔶 | 🔶 |
| 네이티브 다이얼로그 (메시지/열기/저장/폴더) | ✅ | ✅ | ✅ | ✅ | 🔶 |
| 애플리케이션 메뉴 / 컨텍스트 메뉴 | ✅ | ✅ | ✅ | ✅ | 🔶 |
| 키보드 단축키 (글로벌) | ✅ | ✅ | 🔶² | ❌ | ❌ |
| 시스템 트레이 아이콘 + 메뉴 | ✅ | ✅ | 🔶⁴ | ❌ | ❌ |
| 네이티브 알림 | ✅ WinRT | ✅ UserNotifications | ✅ notify-send | ✅ UNNotification | ✅ JNI 브리지 |
| Shell (`openExternal` / `showItemInFolder` / `moveToTrash`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| 클립보드 (텍스트 + 이미지 + 형식 검사) | ✅ | ✅ | ✅ | ✅ | ✅ |
| 자동 시작 (로그인 시 실행) | ✅ Registry | ✅ SMAppService | ✅ XDG .desktop | ❌ | ❌ |
| 딥링크 / 커스텀 URL 스킴 | ✅ Registry | ✅ Launch Services | ✅ XDG MIME | ✅ | ✅ JNI |
| 싱글 인스턴스 + 인자 전달 | ✅ WM_COPYDATA | ✅ NSRunningApp | ✅ Unix 소켓 | ❌ | ❌ |
| 파일시스템 (`__ks.fs.*`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| HTTP fetch (`__ks.http.fetch`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| 윈도우 상태 영속화 | ✅ | ✅ | ✅³ | ❌ | ❌ |

**범례:** ✅ 구현 완료 · 🔶 부분 · ❌ 스텁 (계획)

¹ macOS/Linux/iOS/Android는 `ks://app/` 커스텀 스킴만 지원. `https://app.kalsae/` 형태는 웹뷰 엔진 한계(WKURLSchemeHandler/WebKitGTK는 `http(s)` 스킴을 가로채지 못함)로 Windows 전용. 응답에는 `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`가 포함된다.
² Linux는 `GtkShortcutController`(LOCAL scope) 기반 윈도우 스코프 단축키만 지원. 시스템 전역 단축키는 Wayland 표준 부재로 v1 범위 외.
³ Linux는 크기/최대화/전체화면은 항상 복원하며, 위치는 X11에서만 복원 — Wayland는 컴포지터가 위치를 제어한다.
⁴ Linux는 D-Bus StatusNotifierItem + DBusMenu 직접 구현(AppIndicator3/libayatana 도입 없음). KDE Plasma, Cinnamon, XFCE, Pantheon 및 AppIndicator extension이 활성화된 GNOME에서 동작. 순수 GNOME은 SNI 다이젝트 지원이 없어 install이 경고 로그만 남기고 no-op으로 폴백. 서브메뉴는 v1에서 미지원(평탄 메뉴만).

</details>

---

## CLI Reference

| Command | Description |
|---|---|
| `kalsae new <name>` | Scaffold a new project (Package.swift, App.swift, sample `index.html`) |
| `kalsae dev [--target NAME] [--config FILE] [--skip-dev-command] [--no-wait-dev-server] [--watch] [--watch-interval SECONDS]` | Run with `swift run`; optionally start `build.devCommand`, wait for `build.devServerURL`, and auto-restart on source changes |
| `kalsae build [--debug] [--package] [--webview2 evergreen\|fixed\|auto] [--arch x64\|arm64\|x86] [--config FILE] [--dist PATH] [--allow-missing-dist] [--no-sync-resources] [--icon PATH] [--output DIR] [--zip]` | Integrated frontend+Swift build with dist validation/sync, optional packaging with WebView2 runtime |
| `kalsae doctor [--config FILE] [--strict] [--json]` | Diagnose common local issues (config/dist/WebView2/swift-syntax cache) |
| `kalsae generate bindings [--out FILE] [--module NAME] [inputs...]` | Emit TypeScript types for `@KSCommand` functions |

Source: [Sources/KalsaeCLI/Commands/](Sources/KalsaeCLI/Commands/).

<details>
<summary>🇰🇷 한국어로 보기</summary>

| 명령어 | 설명 |
|---|---|
| `kalsae new <name>` | 새 프로젝트 생성 (Package.swift, App.swift, 샘플 `index.html`) |
| `kalsae dev [--target 이름] [--config 파일] [--skip-dev-command] [--no-wait-dev-server] [--watch] [--watch-interval 초]` | `swift run` 래핑; `build.devCommand` 자동 실행, `build.devServerURL` 대기, 소스 변경 시 자동 재시작 옵션 제공 |
| `kalsae build [--debug] [--package] [--webview2 evergreen\|fixed\|auto] [--arch x64\|arm64\|x86] [--config 파일] [--dist 경로] [--allow-missing-dist] [--no-sync-resources] [--icon 경로] [--output 디렉터리] [--zip]` | 프론트엔드+Swift 통합 빌드(검증/리소스 동기화 포함) 및 WebView2 런타임 포함 패키징 |
| `kalsae doctor [--config 파일] [--strict] [--json]` | 로컬 환경 이슈 진단 (config/dist/WebView2/swift-syntax 캐시) |
| `kalsae generate bindings [--out 파일] [--module 이름] [입력...]` | `@KSCommand` 함수의 TypeScript 타입 생성 |

소스: [Sources/KalsaeCLI/Commands/](Sources/KalsaeCLI/Commands/)

</details>

---

## Security Model

- **Command allowlist** — `security.commandAllowlist` selects which commands JS can invoke (`null` = all registered).
- **Filesystem scope** — `security.fs.allow` / `security.fs.deny` glob patterns with `$APP`, `$HOME`, `$DOCS`, `$TEMP` macros.
- **Shell scope** — `security.shell.openExternalSchemes`, `showItemInFolder`, `moveToTrash` gates.
- **Notification scope** — `security.notifications.post`, `cancel`, `requestPermission` gates.
- **HTTP scope** — `security.http.allow` / `deny` origin patterns, method gating, and default headers for `__ks.http.fetch`.
- **Download scope** — `security.downloads.enabled` gates WebView downloads.
- **Navigation scope** — `security.navigation.allow` gates in-window navigation; rejected URLs can be opened externally.
- **Command rate limit** — `security.commandRateLimit` (token-bucket: `rate`/`burst`) prevents JS from flooding the Swift side.
- **Content-Security-Policy** — injected as both an HTTP header and a `<meta>` tag on the virtual host.
- **DevTools** — opt-in via `security.devtools`; forced `false` in release builds.
- **Context menu / external drop** — `security.contextMenu` (`default` | `disabled`) and `security.allowExternalDrop` (drops are routed to the `__ks.file.drop` event when disabled).

See [Sources/KalsaeCore/Config/KSSecurityConfig.swift](Sources/KalsaeCore/Config/KSSecurityConfig.swift).

<details>
<summary>🇰🇷 한국어로 보기</summary>

- **명령 화이트리스트** — `security.commandAllowlist`로 JS에서 호출 가능한 명령을 제한합니다 (`null`이면 등록된 모든 명령 허용).
- **파일시스템 스코프** — `security.fs.allow` / `security.fs.deny` 글롭 패턴, `$APP`/`$HOME`/`$DOCS`/`$TEMP` 매크로 사용 가능.
- **셸 스코프** — `security.shell.openExternalSchemes`, `showItemInFolder`, `moveToTrash` 게이트.
- **알림 스코프** — `security.notifications.post`, `cancel`, `requestPermission` 게이트.
- **HTTP 스코프** — `security.http.allow`/`deny` 오리진 패턴, 메서드 게이트, `__ks.http.fetch`의 기본 헤더.
- **다운로드 스코프** — `security.downloads.enabled`로 WebView 다운로드 게이트.
- **탐색 스코프** — `security.navigation.allow`로 윈도우 내 탐색 게이트; 거부된 URL은 외부에서 열 수 있음.
- **명령 속도 제한** — `security.commandRateLimit` (토큰 버킷: `rate`/`burst`)으로 JS의 Swift 측 홍수 호출 방지.
- **Content-Security-Policy** — 가상 호스트에 HTTP 헤더와 `<meta>` 태그 양쪽으로 주입됩니다.
- **DevTools** — `security.devtools`로 옵트인. 릴리스 빌드에서는 강제 비활성화됩니다.
- **컨텍스트 메뉴 / 외부 드롭** — `security.contextMenu` (`default` | `disabled`) 와 `security.allowExternalDrop`. 외부 드롭이 비활성화되면 파일 드롭은 `__ks.file.drop` 이벤트로 라우팅됩니다.

상세는 [Sources/KalsaeCore/Config/KSSecurityConfig.swift](Sources/KalsaeCore/Config/KSSecurityConfig.swift) 참고.

</details>

---

## Swift SDK: `KSApp` API Reference

### Boot & Lifecycle

```swift
// Boot from config file
let app = try await KSApp.boot(configURL: url) { registry in /* register commands */ }

// Boot from in-memory config
let app = try await KSApp.boot(config: myConfig) { registry in /* register commands */ }

// Run the message loop
exit(app.run())

// Graceful shutdown
await app.shutdown()
```

### Single Instance

```swift
switch await KSApp.singleInstance(identifier: "dev.example.MyApp") { args in
    // Focus existing window, parse args, etc.
} {
case .relayed: exit(EXIT_SUCCESS)
case .primary: break
}
```

### Deep Links

```swift
// Dispatch deep-link URLs from command-line arguments
app.dispatchDeepLinkURLs(args: CommandLine.arguments)
```

### Native UI Helpers

```swift
// Native message dialog
app.showMessage(KSMessageOptions(title: "Hello", message: "World")) { result in
    print(result)
}

// Native file open dialog
app.openFile(KSOpenFileOptions(allowedTypes: [.text])) { urls in
    print(urls)
}

// Native notification
app.postNotification(KSNotification(title: "Done", body: "Task completed"))

// Set AppUserModelID (Windows toast notifications)
app.setAppUserModelID("dev.example.MyApp")
```

### Lifecycle Callbacks

```swift
// Intercept window close
app.setOnBeforeClose { /* return true to cancel */ false }

// Power management
app.setOnSuspend { /* save state */ }
app.setOnResume { /* restore state */ }
```

### Event Emission

```swift
// Emit event to frontend
try app.emit("custom:event", payload: ["key": "value"])
```

<details>
<summary>🇰🇷 한국어로 보기</summary>

### 부트 & 라이프사이클

```swift
// 설정 파일에서 부트
let app = try await KSApp.boot(configURL: url) { registry in /* 명령 등록 */ }

// 메모리 내 설정에서 부트
let app = try await KSApp.boot(config: myConfig) { registry in /* 명령 등록 */ }

// 메시지 루프 실행
exit(app.run())

// 정리된 종료
await app.shutdown()
```

### 싱글 인스턴스

```swift
switch await KSApp.singleInstance(identifier: "dev.example.MyApp") { args in
    // 기존 윈도우에 포커스, args 파싱 등
} {
case .relayed: exit(EXIT_SUCCESS)
case .primary: break
}
```

### 딥링크

```swift
// 명령줄 인자에서 딥링크 URL 디스패치
app.dispatchDeepLinkURLs(args: CommandLine.arguments)
```

### 네이티브 UI 헬퍼

```swift
// 네이티브 메시지 다이얼로그
app.showMessage(KSMessageOptions(title: "Hello", message: "World")) { result in
    print(result)
}

// 네이티브 파일 열기 다이얼로그
app.openFile(KSOpenFileOptions(allowedTypes: [.text])) { urls in
    print(urls)
}

// 네이티브 알림
app.postNotification(KSNotification(title: "Done", body: "Task completed"))

// AppUserModelID 설정 (Windows 토스트 알림)
app.setAppUserModelID("dev.example.MyApp")
```

### 라이프사이클 콜백

```swift
// 윈도우 닫기 인터셉트
app.setOnBeforeClose { /* true 반환 시 취소 */ false }

// 전원 관리 콜백
app.setOnSuspend { /* 상태 저장 */ }
app.setOnResume { /* 상태 복원 */ }
```

### 이벤트 방출

```swift
// 프론트엔드로 이벤트 방출
try app.emit("custom:event", payload: ["key": "value"])
```

</details>

---

## Roadmap

- Linux global accelerator backend improvements (Wayland ecosystem dependent)
- Auto-updater
- Mobile host ergonomics (iOS integration polish, Android host-side tooling)

<details>
<summary>🇰🇷 한국어로 보기</summary>

- Linux 글로벌 단축키 개선 (Wayland 생태계 의존)
- 자동 업데이트
- 모바일 호스트 경험 개선 (iOS 통합 완성도, Android 호스트 측 툴링)

</details>

---

## Contributing & License

This project is in early development and breaking changes are expected. Issues and pull requests are welcome — please open a discussion first for non-trivial changes.

License: MIT.

<details>
<summary>🇰🇷 한국어로 보기</summary>

이 프로젝트는 초기 개발 단계이며 호환성을 깨는 변경이 발생할 수 있습니다. 이슈와 풀 리퀘스트를 환영합니다. 다만 큰 변경은 먼저 디스커션을 열어 논의해 주세요.

라이선스: MIT.

</details>
