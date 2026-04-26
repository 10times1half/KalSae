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
- Platforms: **Windows** (stable) · **macOS** (preview) · **Linux** (preview)
- WebView engines: WebView2 (Win) · WKWebView (mac) · WebKitGTK 6.0 (Linux)

_🇰🇷 Swift 6.0 + SPM + swift-testing. Windows가 가장 완성도 높음._

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
| Windows 10 1809+ | Visual Studio Build Tools (MSVC 14+); run `./Scripts/fetch-webview2.ps1` once to populate `Vendor/WebView2/` |
| macOS 14+ | none |
| Linux | `apt install libgtk-4-dev libwebkitgtk-6.0-dev libsoup-3.0-dev` |

**Shell rules (Windows):**
- This repo is developed in **PowerShell 5.1 / 7**. Chain commands with `;` —
  **never** `&&`.
- Working directory is `C:\Projects\Kalsae`.

_🇰🇷 `swift build` / `swift test`. Windows는 `./Scripts/fetch-webview2.ps1` 먼저._
_🇰🇷 PowerShell 체이닝은 `;`만 사용 (`&&` 금지)._

---

## 3. Repository Layout

```
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
  KalsaePlatformMac/       AppKit + WKWebView PAL (preview)
  KalsaePlatformLinux/     GTK4 + WebKitGTK PAL (preview)

  CKalsaeWV2/              C++ shim for WebView2 (Windows-only)
  CKalsaeGtk/              C shim for GTK4 (Linux-only)
  CGtk4/, CWebKitGTK/      systemLibrary modulemaps (Linux pkg-config)

Tests/
  KalsaeCLITests/          Packager, BindingsGenerator, ProjectTemplate
  KalsaeCoreTests/         AssetCache/Resolver, IPC, Config, PAL contract tests
  KalsaeMacrosTests/       Macro expansion + diagnostics (uses
                           SwiftSyntaxMacrosTestSupport)

Scripts/
  fetch-webview2.ps1       Downloads WebView2 NuGet → Vendor/WebView2/

.github/workflows/
  phase-windows-build.yml  Windows CI (Swift 6.3.1 via compnerd/gha-setup-swift)
  phase9-macos-e2e.yml     macOS CI
  phase10-linux-e2e.yml    Linux CI
```

_🇰🇷 Sources/Kalsae* = Swift, Sources/CKalsae* = C/C++ 브리지(플랫폼 전용)._

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
- Use `#if os(Windows)` / `os(macOS)` / `os(Linux)` in source files.

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

### macOS
- Deployment target is `macOS 14`.
- PAL surfaces beyond WebView + IPC are stubs (KSMacPlatform.swift).

### Linux
- Requires GTK4 + WebKitGTK 6.0 via pkg-config.
- PAL surfaces beyond WebView + IPC are stubs (KSLinuxPlatform.swift).

_🇰🇷 Windows = 풀 PAL. macOS/Linux = WebView+IPC만 동작 (스텁 외)._

---

## 6. CI Notes

- **Windows CI** uses Swift **6.3.1-RELEASE** (matches local). Earlier 6.0
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

_🇰🇷 Windows CI는 Swift 6.3.1 고정. 성능 단언은 `CI` 환경변수로 완화._

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
- IPC + built-in commands: [Sources/KalsaeCore/IPC/](Sources/KalsaeCore/IPC/)
- Config schema:           [Sources/KalsaeCore/Config/](Sources/KalsaeCore/Config/)
- Sample config:           [Examples/kalsae.sample.json](Examples/kalsae.sample.json)
- Macro implementation:    [Sources/KalsaeMacrosPlugin/KSCommandMacro.swift](Sources/KalsaeMacrosPlugin/KSCommandMacro.swift)
- CLI commands:            [Sources/KalsaeCLI/Commands/](Sources/KalsaeCLI/Commands/)
- Windows PAL:             [Sources/KalsaePlatformWindows/](Sources/KalsaePlatformWindows/)
- WebView2 C++ shim:       [Sources/CKalsaeWV2/src/](Sources/CKalsaeWV2/src/)

When in doubt, grep for an existing `KS*` type that does something similar
and follow its shape rather than inventing a new pattern.

_🇰🇷 새 패턴 만들기 전에 기존 `KS*` 유형을 grep해서 모양을 따라가세요._
