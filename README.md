<<<<<<< HEAD
# Kalsae

> A Swift-native, cross-platform desktop framework for shipping web UIs as small, secure native apps.

![Swift](https://img.shields.io/badge/swift-6.0-orange.svg) ![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg) ![Status](https://img.shields.io/badge/status-experimental-yellow.svg) ![Version](https://img.shields.io/badge/version-0.0.4--phase4-blue.svg)

Kalsae lets you build desktop applications by combining a **native OS shell written in Swift** with a **web frontend** of your choice (Vite, Next.js, plain HTML — anything that produces static assets). It is in the same family as Tauri and Electron, but the host process is pure Swift 6 and the runtime stays small by reusing the OS web engine: **WebView2** on Windows, **WKWebView** on macOS, **WebKitGTK 6.0** on Linux.

> ⚠️ **Experimental.** APIs may change. Windows is the most complete target today; macOS and Linux ship as previews (WebView + IPC only — see the [Platform Support Matrix](#platform-support-matrix)).

<details>
<summary>🇰🇷 한국어로 보기</summary>

**Kalsae**는 **Swift로 작성된 네이티브 OS 셸**과 원하는 **웹 프론트엔드**(Vite, Next.js, 일반 HTML 등)를 결합해 데스크톱 앱을 만드는 프레임워크입니다. Tauri나 Electron과 같은 계열이지만, 호스트 프로세스는 순수 Swift 6이며 OS의 웹 엔진(Windows의 **WebView2**, macOS의 **WKWebView**, Linux의 **WebKitGTK 6.0**)을 그대로 재사용해 런타임 크기를 작게 유지합니다.

> ⚠️ **실험적 단계입니다.** API는 변경될 수 있으며, 현재는 Windows가 가장 완성도가 높습니다. macOS와 Linux는 WebView + IPC만 동작하는 프리뷰 상태입니다([플랫폼 지원 매트릭스](#platform-support-matrix) 참고).

</details>

---

## Why Kalsae

- **Swift-native host.** No Node.js, no Rust toolchain on the desktop side. The shell, IPC, and platform integrations are all Swift 6 with typed throws and macros.
- **Small runtime.** No bundled Chromium. On Windows, WebView2 is fetched from Microsoft and bundled at package time; on macOS/Linux the system web engine is used.
- **Declarative configuration.** A single `Kalsae.json` describes windows, menus, tray, security, and notifications. No imperative bootstrap code required for most apps.
- **Type-safe IPC.** Expose Swift functions to JavaScript with the `@KSCommand` macro; arguments and return values are `Codable`. Optionally generate matching TypeScript types with `kalsae generate bindings`.

<details>
<summary>🇰🇷 한국어로 보기</summary>

- **Swift 네이티브 호스트** — 데스크톱 측에 Node.js나 Rust 툴체인이 필요 없습니다. 셸·IPC·플랫폼 통합 모두 Swift 6(typed throws, 매크로 활용)로 작성되었습니다.
- **작은 런타임** — Chromium을 번들링하지 않습니다. Windows에서는 패키징 시 Microsoft에서 WebView2를 받아 함께 배포하고, macOS/Linux에서는 OS 내장 엔진을 그대로 사용합니다.
- **선언형 설정** — `Kalsae.json` 한 파일로 윈도우·메뉴·트레이·보안·알림을 정의합니다. 대부분의 앱은 별도의 부트스트랩 코드를 작성할 필요가 없습니다.
- **타입 안전 IPC** — `@KSCommand` 매크로로 Swift 함수를 JavaScript에 노출합니다. 인자와 반환값은 `Codable`이며, `kalsae generate bindings`로 TypeScript 타입을 자동 생성할 수 있습니다.

</details>

---

## Status

| Component | Stage | Notes |
|---|---|---|
| Core IPC, Config, Macros | Stable | Production-ready |
| **Windows** (Win32 + WebView2) | Stable | Full PAL: window / dialog / menu / tray / notification / shell / clipboard |
| **macOS** (WKWebView) | Preview | WebView + IPC only; PAL surfaces are stubs |
| **Linux** (WebKitGTK 6.0) | Preview | WebView + IPC only; PAL surfaces are stubs |

<details>
<summary>🇰🇷 한국어로 보기</summary>

| 구성요소 | 단계 | 비고 |
|---|---|---|
| 코어 IPC · 설정 · 매크로 | 안정 | 프로덕션 사용 가능 |
| **Windows** (Win32 + WebView2) | 안정 | 윈도우/다이얼로그/메뉴/트레이/알림/셸/클립보드 PAL 전체 구현 |
| **macOS** (WKWebView) | 프리뷰 | WebView + IPC만 동작, 그 외 PAL은 스텁 |
| **Linux** (WebKitGTK 6.0) | 프리뷰 | WebView + IPC만 동작, 그 외 PAL은 스텁 |

</details>

---

## Quick Start

### Prerequisites

- **Swift 6.0+** (typed throws, macros)
- **Windows 10 1809+** with Visual Studio Build Tools (MSVC for the C++ shim). The WebView2 runtime is fetched automatically by [Scripts/fetch-webview2.ps1](Scripts/fetch-webview2.ps1).
- **macOS** 10.14+ (no extra deps)
- **Linux**: `apt install libgtk-4-dev libwebkitgtk-6.0-dev`

### Try the bundled demo

```bash
git clone <this-repo>
cd Kalsae
swift build
swift run kalsae-demo
```

### Scaffold a new app

```bash
kalsae new MyDesktopApp
cd MyDesktopApp
kalsae dev                     # run with hot iteration
kalsae build --package         # release build + WebView2 bundling
```

<details>
<summary>🇰🇷 한국어로 보기</summary>

### 사전 요구사항

- **Swift 6.0 이상** (typed throws, 매크로)
- **Windows 10 1809 이상** + Visual Studio Build Tools (C++ shim용 MSVC). WebView2 런타임은 [Scripts/fetch-webview2.ps1](Scripts/fetch-webview2.ps1)이 자동으로 받아옵니다.
- **macOS** 10.14 이상 (추가 의존성 없음)
- **Linux**: `apt install libgtk-4-dev libwebkitgtk-6.0-dev`

### 데모 실행

```bash
git clone <this-repo>
cd Kalsae
swift build
swift run kalsae-demo
```

### 새 프로젝트 만들기

```bash
kalsae new MyDesktopApp
cd MyDesktopApp
kalsae dev                     # 개발 모드 실행
kalsae build --package         # 릴리스 빌드 + WebView2 번들링
```

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

Top-level sections: `app`, `build`, `windows[]`, `security`, optional `tray`, `menu`, `notifications`. See [Examples/kalsae.sample.json](Examples/kalsae.sample.json) for a full reference and [Sources/KalsaeCore/Config/](Sources/KalsaeCore/Config/) for schema sources.

<details>
<summary>🇰🇷 한국어로 보기</summary>

최소한의 `Kalsae.json` 예시는 위와 같습니다. 최상위 섹션은 `app`, `build`, `windows[]`, `security`이며 선택적으로 `tray`, `menu`, `notifications`를 지정할 수 있습니다. 전체 예시는 [Examples/kalsae.sample.json](Examples/kalsae.sample.json), 스키마 소스는 [Sources/KalsaeCore/Config/](Sources/KalsaeCore/Config/)를 참고하세요.

`security` 섹션은 다음 항목으로 앱을 보호합니다:
- `commandAllowlist` — JS에서 호출 가능한 명령 화이트리스트(`null`이면 등록된 모든 명령 허용)
- `fs.allow` / `fs.deny` — 파일시스템 접근 글롭 패턴 (`$HOME`, `$DOCS`, `$TEMP` 매크로 사용 가능)
- `csp` — Content-Security-Policy 헤더와 `<meta>` 태그로 주입
- `devtools` — DevTools 활성화 (릴리스 빌드는 강제로 `false`)

</details>

---

## JavaScript API

Kalsae injects a runtime under `window.__KS_` exposing six namespaces. All methods return `Promise`s.

| Namespace | Purpose | Example |
|---|---|---|
| `__KS_.invoke(cmd, args)` | Call a Swift `@KSCommand` or built-in command | `await __KS_.invoke("greet", { name: "Alice" })` |
| `__KS_.window` | Window state and geometry (24 methods) | `await __KS_.window.toggleMaximize()` |
| `__KS_.shell` | Open URLs, reveal files, trash files | `await __KS_.shell.openExternal("https://...")` |
| `__KS_.clipboard` | Read/write text, format check | `await __KS_.clipboard.writeText("hi")` |
| `__KS_.app` | Quit, environment info, hide/show | `await __KS_.app.environment()` |
| `__KS_.events` | `on` / `off` / `once` / `emit` | `__KS_.events.on("greet:done", cb)` |
| `__KS_.log` | Native logger (`trace`/`debug`/`info`/`warn`/`error`) | `__KS_.log.info("ready")` |

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

Kalsae는 페이지에 `window.__KS_` 런타임을 주입하며, 아래 6개 네임스페이스를 제공합니다. 모든 메서드는 `Promise`를 반환합니다.

| 네임스페이스 | 용도 | 예시 |
|---|---|---|
| `__KS_.invoke(cmd, args)` | Swift `@KSCommand` 또는 내장 명령 호출 | `await __KS_.invoke("greet", { name: "Alice" })` |
| `__KS_.window` | 윈도우 상태/기하 (24개 메서드) | `await __KS_.window.toggleMaximize()` |
| `__KS_.shell` | URL 열기, 파일탐색기 열기, 휴지통 이동 | `await __KS_.shell.openExternal("https://...")` |
| `__KS_.clipboard` | 텍스트 읽기/쓰기, 형식 검사 | `await __KS_.clipboard.writeText("hi")` |
| `__KS_.app` | 종료, 환경 정보, 표시/숨김 | `await __KS_.app.environment()` |
| `__KS_.events` | `on` / `off` / `once` / `emit` | `__KS_.events.on("greet:done", cb)` |
| `__KS_.log` | 네이티브 로거 (`trace`/`debug`/`info`/`warn`/`error`) | `__KS_.log.info("ready")` |

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
| `__ks.app.*` + `__ks.environment` + `__ks.log` | 5 | `quit`, `environment`, `hide`, `show`, `log` |

Source: [Sources/KalsaeCore/IPC/](Sources/KalsaeCore/IPC/). All built-ins are gated by the `security` config — anything not allowed by `commandAllowlist`, `shell.*`, or `notifications.*` returns `commandNotAllowed`.

<details>
<summary>🇰🇷 한국어로 보기</summary>

별도 등록 없이 `__ks.` 접두사로 즉시 사용 가능한 명령 목록입니다. 모든 내장 명령은 `security` 설정의 영향을 받으며, `commandAllowlist`/`shell.*`/`notifications.*`에서 허용되지 않은 명령은 `commandNotAllowed` 에러를 반환합니다. 소스는 [Sources/KalsaeCore/IPC/](Sources/KalsaeCore/IPC/)에 있습니다.

</details>

---

## Platform Support Matrix

| Feature | Windows | macOS | Linux |
|---|:---:|:---:|:---:|
| WebView load + IPC bridge | ✅ | ✅ | ✅ |
| Custom virtual host (`https://app.kalsae/` / `ks://app/`) | ✅ | 🔶 | 🔶 |
| DevTools | ✅ | ✅ | ✅ |
| Window create / close / show / hide | ✅ | 🔶 | 🔶 |
| Window minimize / maximize / fullscreen | ✅ | ❌ | ❌ |
| Window position / size / min-max bounds | ✅ | ❌ | ❌ |
| Theme (light / dark / system) | ✅ | ❌ | ❌ |
| Multi-window | 🔶 | ❌ | ❌ |
| Native dialogs (message / open / save / folder) | ✅ | ❌ | ❌ |
| Application & context menus | ✅ | ❌ | ❌ |
| Keyboard accelerators | ✅ | ❌ | ❌ |
| System tray icon + menu | ✅ | ❌ | ❌ |
| Native notifications (WinRT toast) | ✅ | ❌ | ❌ |
| Shell (`openExternal` / `showItemInFolder` / `moveToTrash`) | ✅ | ❌ | ❌ |
| Clipboard (text + format check) | ✅ | ❌ | ❌ |

**Legend:** ✅ implemented · 🔶 partial / preview · ❌ stub (planned)

<details>
<summary>🇰🇷 한국어로 보기</summary>

| 기능 | Windows | macOS | Linux |
|---|:---:|:---:|:---:|
| WebView 로딩 + IPC 브리지 | ✅ | ✅ | ✅ |
| 가상 호스트 (`https://app.kalsae/` / `ks://app/`) | ✅ | 🔶 | 🔶 |
| 개발자 도구 | ✅ | ✅ | ✅ |
| 윈도우 생성/종료/표시/숨김 | ✅ | 🔶 | 🔶 |
| 윈도우 최소/최대화/전체화면 | ✅ | ❌ | ❌ |
| 윈도우 위치/크기/최소-최대 제한 | ✅ | ❌ | ❌ |
| 테마 (라이트/다크/시스템) | ✅ | ❌ | ❌ |
| 다중 윈도우 | 🔶 | ❌ | ❌ |
| 네이티브 다이얼로그 (메시지/열기/저장/폴더) | ✅ | ❌ | ❌ |
| 애플리케이션 메뉴 / 컨텍스트 메뉴 | ✅ | ❌ | ❌ |
| 키보드 단축키 | ✅ | ❌ | ❌ |
| 시스템 트레이 아이콘 + 메뉴 | ✅ | ❌ | ❌ |
| 네이티브 알림 (WinRT toast) | ✅ | ❌ | ❌ |
| Shell (`openExternal` / `showItemInFolder` / `moveToTrash`) | ✅ | ❌ | ❌ |
| 클립보드 (텍스트 + 형식 검사) | ✅ | ❌ | ❌ |

**범례:** ✅ 구현 완료 · 🔶 부분 / 프리뷰 · ❌ 스텁 (계획)

</details>

---

## CLI Reference

| Command | Description |
|---|---|
| `kalsae new <name>` | Scaffold a new project (Package.swift, App.swift, sample `index.html`) |
| `kalsae dev [--target NAME]` | Run with `swift run`; optionally pick an executable target |
| `kalsae build [--debug] [--package] [--webview2 evergreen\|fixed\|auto] [--arch x64\|arm64\|x86] [--config FILE] [--icon PATH] [--output DIR] [--zip]` | Release build, optional packaging with WebView2 runtime |
| `kalsae generate bindings [--out FILE] [--module NAME] [inputs...]` | Emit TypeScript types for `@KSCommand` functions |

Source: [Sources/KalsaeCLI/Commands/](Sources/KalsaeCLI/Commands/).

<details>
<summary>🇰🇷 한국어로 보기</summary>

| 명령어 | 설명 |
|---|---|
| `kalsae new <name>` | 새 프로젝트 생성 (Package.swift, App.swift, 샘플 `index.html`) |
| `kalsae dev [--target 이름]` | `swift run` 래핑; 실행 타깃 선택 가능 |
| `kalsae build [--debug] [--package] [--webview2 evergreen\|fixed\|auto] [--arch x64\|arm64\|x86] [--config 파일] [--icon 경로] [--output 디렉터리] [--zip]` | 릴리스 빌드 및 WebView2 런타임 포함 패키징 |
| `kalsae generate bindings [--out 파일] [--module 이름] [입력...]` | `@KSCommand` 함수의 TypeScript 타입 생성 |

소스: [Sources/KalsaeCLI/Commands/](Sources/KalsaeCLI/Commands/)

</details>

---

## Security Model

- **Command allowlist** — `security.commandAllowlist` selects which commands JS can invoke (`null` = all registered).
- **Filesystem scope** — `security.fs.allow` / `security.fs.deny` glob patterns with `$HOME`, `$DOCS`, `$TEMP` macros.
- **Content-Security-Policy** — injected as both an HTTP header and a `<meta>` tag on the virtual host.
- **DevTools** — opt-in via `security.devtools`; forced `false` in release builds.
- **Context menu / external drop** — `security.contextMenu` (`default` | `disabled`) and `security.allowExternalDrop` (drops are routed to the `__ks.file.drop` event when disabled).

See [Sources/KalsaeCore/Config/KSSecurityConfig.swift](Sources/KalsaeCore/Config/KSSecurityConfig.swift).

<details>
<summary>🇰🇷 한국어로 보기</summary>

- **명령 화이트리스트** — `security.commandAllowlist`로 JS에서 호출 가능한 명령을 제한합니다 (`null`이면 등록된 모든 명령 허용).
- **파일시스템 스코프** — `security.fs.allow` / `security.fs.deny` 글롭 패턴, `$HOME`/`$DOCS`/`$TEMP` 매크로 사용 가능.
- **Content-Security-Policy** — 가상 호스트에 HTTP 헤더와 `<meta>` 태그 양쪽으로 주입됩니다.
- **DevTools** — `security.devtools`로 옵트인. 릴리스 빌드에서는 강제 비활성화됩니다.
- **컨텍스트 메뉴 / 외부 드롭** — `security.contextMenu` (`default` | `disabled`) 와 `security.allowExternalDrop`. 외부 드롭이 비활성화되면 파일 드롭은 `__ks.file.drop` 이벤트로 라우팅됩니다.

상세는 [Sources/KalsaeCore/Config/KSSecurityConfig.swift](Sources/KalsaeCore/Config/KSSecurityConfig.swift) 참고.

</details>

---

## Roadmap

- Complete macOS PAL (window / menu / dialog / tray / notifications)
- Complete Linux PAL (GTK4 widgets, libnotify, AppIndicator)
- Multi-window orchestration
- Auto-updater
- Mobile (iOS/Android) exploration

<details>
<summary>🇰🇷 한국어로 보기</summary>

- macOS PAL 완성 (윈도우 / 메뉴 / 다이얼로그 / 트레이 / 알림)
- Linux PAL 완성 (GTK4 위젯, libnotify, AppIndicator)
- 다중 윈도우 오케스트레이션
- 자동 업데이트
- 모바일(iOS/Android) 검토

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
=======
# KalSae
A modern cross-platform app framework for Swift using WebView. Build beautiful desktop and mobile apps with one Swift codebase.
>>>>>>> 248e498382a1eaeb2f6f4bb74fe7b51a28dc3657
