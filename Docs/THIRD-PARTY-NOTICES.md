# Third-Party Notices

> 한글 핵심 요약은 각 섹션 끝의 _🇰🇷_ 줄을 참고하세요.

Kalsae itself is distributed under the **MIT License** (see [LICENSE](../LICENSE)).
However, Kalsae **dynamically links** to OS web engines and native system
libraries at runtime, and **statically links** a small number of Apache-2.0
licensed Swift packages at build time. End-user distributions of any
application built with Kalsae — MSIX, AppImage, `.app`, `.apk`, App Store /
Play Store packages — **must reproduce the third-party license notices below**
either as a bundled `NOTICE` / `THIRD-PARTY-LICENSES.txt` file or via an
in-app "About / Licenses" screen.

This document is the canonical source. Application developers may copy its
contents verbatim, or reference it by URL.

_🇰🇷 Kalsae 본체는 MIT. 배포물에는 이 문서의 내용을 동봉하거나 앱 내 "정보 / 라이선스" 화면을 통해 노출해야 한다._

---

## 1. Scope

A Kalsae-based application combines three categories of third-party code:

| Category | Examples | Linkage | Bundled in app? |
|---|---|---|---|
| **Static Swift dependencies** | swift-argument-parser, swift-log | Static (SwiftPM) | ✅ Inside the executable |
| **OS-provided components** | WebView2 runtime, WKWebView, Android WebView | System | ❌ Provided by the OS |
| **System libraries (Linux)** | WebKitGTK 6.0, GTK 4, GLib, libsoup-3.0, libsecret-1 | Dynamic (pkg-config) | ❌ Provided by the distro |

The notice obligations differ per category — see §2.

_🇰🇷 정적 Swift 의존성은 바이너리 안에 포함되므로 라이선스 본문을 반드시 동봉. OS 컴포넌트와 시스템 라이브러리는 동적 링크/시스템 제공이므로 고지 텍스트만 동봉하면 된다._

---

## 2. Distribution Obligations

### 2.1 MIT / Apache-2.0 dependencies (statically linked)

Reproduce the full license text in your distribution. The combined notice for
all Apache-2.0 Swift packages is provided in §4.

### 2.2 LGPL system libraries (Linux — WebKitGTK, GTK, GLib, libsoup, libsecret)

LGPL-2.1 (and LGPL-2 for libsoup) requires that the user be able to **replace
the linked library with a modified version**. Kalsae satisfies this by:

1. **Never bundling** the `.so` files inside the AppImage / .deb / .rpm /
   tarball. They must be resolved via the system package manager
   (`apt install libwebkitgtk-6.0-dev libgtk-4-dev libsoup-3.0-dev libsecret-1-dev`).
2. **Never statically linking** these libraries. Build flags come exclusively
   from `pkg-config --libs <pkg>` which emits `-l<name>` (dynamic).
3. **Reproducing the LGPL notice** (§3) in the distributed `NOTICE` file or
   in-app About screen.

If any of (1)–(3) is violated, the resulting binary is **not LGPL-compliant**
and must not be redistributed.

### 2.3 OS-provided components (WebView2 / WKWebView / Android WebView)

These are not redistributed by Kalsae. Their licenses bind end users via the
OS EULA — no additional notice obligation falls on the app, **except** that
the Microsoft WebView2 redistributable SDK terms forbid bundling the
WebView2 runtime installer itself; Kalsae only links the loader stub
(`WebView2LoaderStatic`) which is permitted.

_🇰🇷 정적: 본문 동봉. LGPL: ① 번들 금지 ② 정적 링크 금지 ③ 고지 동봉. OS 컴포넌트: 추가 의무 없음 (WebView2 런타임 인스톨러 번들만 금지)._

---

## 3. LGPL Component Notices (Linux)

### 3.1 WebKitGTK 6.0

- License: **LGPL-2.1** (some components GPL-2 / BSD — see project for breakdown)
- Source: <https://webkit.org/>
- Distro package: `libwebkitgtk-6.0-0` (runtime), `libwebkitgtk-6.0-dev` (build)
- Used by: `Sources/KalsaePlatformLinux/`, `Sources/CKalsaeGtk/`,
  `Sources/CWebKitGTK/`
- Notice text (verbatim): see [LGPL-2.1 full text](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt)

### 3.2 GTK 4

- License: **LGPL-2.1-or-later**
- Source: <https://gitlab.gnome.org/GNOME/gtk>
- Distro package: `libgtk-4-1` (runtime), `libgtk-4-dev` (build)
- Used by: `Sources/KalsaePlatformLinux/`, `Sources/CKalsaeGtk/`, `Sources/CGtk4/`

### 3.3 GLib / GObject / GIO

- License: **LGPL-2.1-or-later**
- Source: <https://gitlab.gnome.org/GNOME/glib>
- Distro package: `libglib2.0-0` (runtime), `libglib2.0-dev` (build)
- Used by: same modules as GTK 4 (transitive dep)

### 3.4 libsoup 3.0

- License: **LGPL-2.0-or-later**
- Source: <https://gitlab.gnome.org/GNOME/libsoup>
- Distro package: `libsoup-3.0-0` (runtime), `libsoup-3.0-dev` (build)
- Used by: WebKitGTK (transitive HTTP stack)

### 3.5 libsecret 1

- License: **LGPL-2.1-or-later**
- Source: <https://gitlab.gnome.org/GNOME/libsecret>
- Distro package: `libsecret-1-0` (runtime), `libsecret-1-dev` (build)
- Used by: `Sources/KalsaePlatformLinux/PAL/KSLinuxCredentialBackend.swift`,
  `Sources/CLibSecret/`
- Purpose: Secret Service (D-Bus) integration for `__KS_.secret.*` IPC —
  delegates to GNOME Keyring / KWallet / KeePassXC according to the
  user's desktop session.

_🇰🇷 모두 LGPL — 동적 링크 + 시스템 패키지 의존 + LGPL-2.1 본문 동봉이면 호환._

---

## 4. Apache-2.0 Dependencies (statically linked into the executable)

The following packages are pulled via SwiftPM and **statically linked** into
the final binary. Their NOTICE files must be reproduced in your distribution.

| Package | Version pin | Repo |
|---|---|---|
| swift-argument-parser | from 1.7.1 | <https://github.com/apple/swift-argument-parser> |
| swift-log | from 1.6.0 | <https://github.com/apple/swift-log> |
| swift-syntax | exact 602.0.0 (build-time only) | <https://github.com/swiftlang/swift-syntax> |

Each is licensed under the **Apache License, Version 2.0**. Full text:
<https://www.apache.org/licenses/LICENSE-2.0.txt>.

Per Apache-2.0 §4, distributions must:

- Retain the LICENSE and any NOTICE file shipped by these packages.
- State that derivative works (your application) may be licensed differently.

The Swift Standard Library and Foundation (also Apache-2.0 with Runtime
Library Exception) are included under the Swift toolchain license and do
not require additional notice when redistributed as compiled binary.

_🇰🇷 Apache-2.0는 LICENSE/NOTICE 보존 + 파생 저작물 라이선스 명시만 하면 됨._

---

## 5. Microsoft WebView2 (Windows)

- **Runtime**: distributed and updated by Microsoft via Windows Update /
  Edge installer. **Not** bundled by Kalsae. Governed by the end user's
  Windows EULA.
- **SDK loader** (`WebView2LoaderStatic` / `WebView2Loader.dll`): redistributed
  under the **Microsoft Software License Terms for Microsoft Edge WebView2
  SDK** (<https://aka.ms/webview2/sdk-license>).
- The SDK terms permit dynamic linking + redistribution of the loader DLL
  with the developer's application. Kalsae uses `kalsae build` (or
  `Scripts/stage-webview2-loader.ps1`) to stage `WebView2Loader.dll` alongside
  the produced executable.

The SDK license text must be reproduced in any distribution that includes the
`WebView2Loader.dll` redistributable. See [Vendor/WebView2/](../Sources/CKalsaeWV2/Vendor/)
after `Scripts/fetch-webview2.ps1`.

_🇰🇷 WebView2 런타임은 OS 책임, 로더 DLL은 MS SDK 라이선스 본문 동봉 필요._

---

## 6. Apple SDK Components (macOS / iOS)

WKWebView, AppKit, UIKit, UserNotifications, Security.framework, Foundation
are part of the Apple SDK and governed by the macOS / iOS Software License
Agreement and Apple Developer Program License Agreement. No additional
notice obligation falls on the application beyond Apple's standard EULA.

_🇰🇷 Apple SDK는 OS/개발자 계약에 종속, 추가 고지 불필요._

---

## 7. Android Components

Android WebView, the Android Framework, and androidx libraries used by the
sample project ([Samples/KalsaeAndroidSample/](../Samples/KalsaeAndroidSample/))
are licensed under **Apache-2.0**. Distributions on Play Store / sideloaded
APKs must include the Apache-2.0 LICENSE and any NOTICE files shipped with
the androidx artifacts used.

_🇰🇷 Android 측은 Apache-2.0 — LICENSE/NOTICE 동봉._

---

## 8. How to bundle this notice in your app

### 8.1 Static file (recommended)

Copy this file into your application's `Resources/` directory and reference
it from your About screen:

```text
yourapp/
  Resources/
    THIRD-PARTY-NOTICES.md     ← copy of this file (or `NOTICE` plain text)
```

### 8.2 In-app About / Licenses dialog

Kalsae's IPC layer exposes asset reads via `__KS_.asset.read`. Embed the
notice as a frontend asset and render it inside your About modal. Example:

```js
const notice = await window.__KS_.asset.readText("THIRD-PARTY-NOTICES.md");
showAboutDialog(notice);
```

### 8.3 Future automation

The `kalsae build` packager will be extended in the future to automatically
copy `Docs/THIRD-PARTY-NOTICES.md` into the dist tree as `NOTICE.txt`. Until
then, application authors are responsible for manual inclusion.

_🇰🇷 일단은 수동 복사 또는 in-app About 화면 노출. 추후 packager가 자동 복사하도록 확장 예정._

---

## 9. Reporting issues

License questions or notice omissions: open an issue at
<https://github.com/10times1half/Kalsae/issues> with the `licensing` label.

---

## Changelog

| Date | Change |
|---|---|
| 2026-05-16 | Initial revision: covers MIT (Kalsae), LGPL (Linux system libs incl. libsecret-1), Apache-2.0 (SwiftPM deps), MS WebView2 SDK, Apple SDK, Android. |
