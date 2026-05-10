# RFC-004: Platform PAL Code Review & Quality Assessment

| Metadata | |
|---|---|
| **Author** | AI Code Review (Cline) |
| **Status** | Draft |
| **Created** | 2026-05-09 |
| **Target** | All 5 platform PAL backends (Windows, macOS, Linux, iOS, Android) |

---

## Abstract

This document presents a rigorous code review of all Kalsae Platform Abstraction Layer
(PAL) backends across five platforms. The review covers code quality, correctness,
consistency, Swift 6 concurrency safety, and adherence to the project's coding
conventions defined in `AGENTS.md`.

---

## Scope

All files under:

| Platform | Directory |
|---|---|
| Windows | `Sources/KalsaePlatformWindows/PAL/` |
| macOS | `Sources/KalsaePlatformMac/PAL/` |
| Linux | `Sources/KalsaePlatformLinux/PAL/` |
| iOS | `Sources/KalsaePlatformIOS/PAL/` |
| Android | `Sources/KalsaePlatformAndroid/PAL/` |

---

## Severity Classification

| Level | Meaning |
|---|---|
| 🔴 **CRITICAL** | Protocol contract violation; app does not function correctly |
| 🟠 **HIGH** | Significant quality, safety, or consistency issue |
| 🟡 **MEDIUM** | Improvement recommended; not blocking |
| 🔵 **INFO** | Observation; no action required immediately |

---

## 🔴 CRITICAL — Immediate Fix Required

### 1. `KSiOSWindowBackend` — All window state methods are no-op

**File:** `Sources/KalsaePlatformIOS/PAL/KSiOSWindowBackend.swift`

```swift
public func show(_ handle: KSWindowHandle) async throws(KSError) {
    try await ensureHandleExists(handle)  // no actual show
}
public func hide(_ handle: KSWindowHandle) async throws(KSError) {
    try await ensureHandleExists(handle)  // no hide
}
public func setTitle(_ handle: KSWindowHandle, title: String) async throws(KSError) {
    _ = title
    try await ensureHandleExists(handle)  // no setTitle
}
```

**Problem:** `show`, `hide`, `focus`, `setTitle`, `setSize` etc. only verify handle
existence without performing any actual window operation. The iOS PAL does not
create or control any `UIWindow`/`UIViewController`.

**Recommendation:** Implement actual `UIWindow` + `WKWebView` creation and control,
or throw `KSError.unsupportedPlatform(...)` consistently.

---

### 2. `KSiOSMenuBackend` / `KSAndroidMenuBackend` — Complete no-op

**Files:**
- `Sources/KalsaePlatformIOS/PAL/KSiOSMenuBackend.swift`
- `Sources/KalsaePlatformAndroid/PAL/KSAndroidMenuBackend.swift`

```swift
public func installAppMenu(_ items: [KSMenuItem]) async throws(KSError) {
    _ = items  // does nothing
}
```

**Problem:** Protocol is "implemented" but no actual menu installation occurs.
iOS could use `UIMenu`/`UIAction`; Android could use `PopupMenu`. Silent no-op
makes debugging extremely difficult.

**Recommendation:** Either provide real implementations or throw
`KSError.unsupportedPlatform(...)` to give callers a clear signal.

---

### 3. `KSiOSWindowBackend.create()` — Does not create an actual window

```swift
public func create(_ config: KSWindowConfig) async throws(KSError) -> KSWindowHandle {
    await MainActor.run {
        KSiOSHandleRegistry.shared.register(label: config.label)  // registry only
    }
}
```

**Problem:** No `UIWindow`/`WKWebView` is created. `webView(for:)` also only
looks up the registry, but `registerWebView` is never called within the iOS PAL.

---

### 4. `KSAndroidClipboardBackend.readImage()` / `writeImage()` — Silent no-op

```swift
public func readImage() async throws(KSError) -> Data? { nil }
public func writeImage(_ image: Data) async throws(KSError) { _ = image }
```

**Problem:** If image clipboard is unsupported, the method should throw
`KSError.unsupportedPlatform(...)`. Returning `nil` and silent no-op mislead
callers into thinking the operation succeeded.

---

## 🟠 HIGH — Significant Quality Issues

### 5. `Result.unwrap()` Duplicate Definition

**Windows** (`KSWin32HandleRegistry.swift`):
```swift
extension Result where Failure == KSError {
    func unwrap() throws(KSError) -> Success { ... }
}
```

**macOS** (`KSMacWindowBackend.swift`):
```swift
extension Result where Failure == KSError {
    fileprivate func unwrap() throws(KSError) -> Success { ... }
}
```

**Problem:** Identical `Result` extension defined in two places with different
access levels (`internal` vs `fileprivate`). Should be defined once in
`KalsaeCore` and shared across all platforms.

**Recommendation:** Move to `KalsaeCore` as `internal extension`.

---

### 6. `KSMacDialogBackend.saveFile()` — Missing `beginSheetModal`

```swift
let nsParent = resolveParent(parent)
let response =
    nsParent != nil
    ? panel.runModal().rawValue == NSApplication.ModalResponse.OK.rawValue
        ? NSApplication.ModalResponse.OK : .cancel
    : panel.runModal()
```

**Problem:** `openFile` and `selectFolder` use `await panel.beginSheetModal(for:)`,
but `saveFile` calls `runModal()` even when a parent window exists. Inconsistent UX.

---

### 7. `KSMacSingleInstance` — Argument forwarding via `NSWorkspace.openApplication` is unreliable

```swift
let config = NSWorkspace.OpenConfiguration()
config.arguments = Array(args.dropFirst())
NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in }
```

**Problem:** `NSWorkspace.openApplication`'s `arguments` parameter is not
guaranteed to work outside sandboxed environments or for non-bundle executables.
Apple's documentation states arguments may be ignored for `.app` bundles.

---

### 8. `KSLinuxWindowBackend.create()` — Unnecessary `switch` on `Result`

```swift
switch result {
case .success(let handle): return handle
case .failure(let error): throw error
}
```

**Problem:** `Result` is unwrapped via verbose `switch` instead of
`try result.unwrap()`. This pattern repeats in `runMain()` and `resolve()`.
Windows/macOS use `try result.unwrap()` consistently.

---

### 9. `KSLinuxDialogBackend` — Repeated `withCheckedContinuation` + `Task { @MainActor }` pattern

```swift
await withCheckedContinuation { (cont: CheckedContinuation<[URL], Never>) in
    Task { @MainActor in ... }
}
```

**Problem:** This pattern is repeated 4 times (`openFile`, `saveFile`,
`selectFolder`, `message`). Should be extracted into a helper function.

---

### 10. `KSLinuxNotificationBackend` — `Process.waitUntilExit()` blocks the calling thread

```swift
private func runProcess(_ executable: String, args: [String]) async -> Bool {
    let task = Process()
    ...
    task.waitUntilExit()  // synchronous blocking
    ...
}
```

**Problem:** `waitUntilExit()` blocks the current thread inside an `async` function,
wasting the cooperative thread pool. Should use `terminationHandler` or an
`async` wrapper.

---

### 11. `KSLinuxSingleInstance` — Raw POSIX socket API safety

```swift
let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
...
close(fd)
```

**Problem:** POSIX socket error handling is incomplete (no `EINTR` handling).
The `Task.detached` accept loop runs forever with no graceful shutdown mechanism
on app termination.

---

### 12. `KSWindowsTrayBackend` / `KSMacTrayBackend` — `nonisolated init` on `@MainActor` class

```swift
@MainActor
public final class KSWindowsTrayBackend: KSTrayBackend {
    public nonisolated init() {}
```

**Problem:** `nonisolated init` allows initialization outside the main actor,
risking access to `@MainActor` properties (e.g., `messageWindow`) before they
are initialized.

---

## 🟡 MEDIUM — Improvements Recommended

### 13. `KSMacWindowBackend` — File-local `Result` extension

`KSMacWindowBackend.swift` lines 6-17 define a `fileprivate` extension on
`Result where Failure == KSError`. Duplicates the `internal` one in
`KSWin32HandleRegistry.swift`. (Same as #5.)

### 14. `KSLinuxWindowBackend` — `nonisolated(unsafe)` warning flags

```swift
nonisolated(unsafe) private static var didWarnTaskbarProgress = false
nonisolated(unsafe) private static var didWarnOverlay = false
nonisolated(unsafe) private static let warnLock = NSLock()
```

`nonisolated(unsafe)` bypasses Swift 6 isolation rules. While protected by
`NSLock`, using `actor` or `@MainActor` static stored properties would be safer.

### 15. `KSWindowsDeepLinkBackend` / `KSWindowsAutostartBackend` — Duplicated `resolveModulePath()`

Identical `GetModuleFileNameW` loop logic exists in both files. Should be
extracted to a shared helper.

### 16. `KSLinuxDeepLinkBackend.shell()` / `KSLinuxNotificationBackend.runProcess()` — Duplicated process runner

Both files define nearly identical `Process` execution helpers.

### 17. `KSLinuxShellBackend` — Inconsistent error code

```swift
throw KSError(code: .io, message: "...")
```

All other platforms use `.ioFailed`. Linux uses `.io` inconsistently.

### 18. `KSiOSShellBackend.openExternal()` — Redundant `canOpenURL` + `open` double call

```swift
let opened = await MainActor.run { UIApplication.shared.canOpenURL(url) }
if !opened { throw ... }
await MainActor.run { UIApplication.shared.open(url) }
```

`canOpenURL` may always return `true` on iOS 14+ with
`LSSupportsOpeningDocumentsInPlace`. Using `open`'s completion handler is more
accurate.

### 19. `KSAndroidDeepLinkBackend` — `nonisolated(unsafe) static var knownSchemes`

```swift
public nonisolated(unsafe) static var knownSchemes: Set<String> = []
```

Global mutable state exposed as `nonisolated(unsafe)`. Should be protected by
an `Actor` or `NSLock`.

---

## 🔵 INFO — Observations

### 20. Windows PAL `KSSendableBox` usage pattern

`KSWindowsDialogBackend` uses `KSSendableBox` to pass non-Sendable values across
`MainActor` boundaries. This is creative but requires careful use since the type
is `@unchecked Sendable`.

### 21. macOS `KSMacTrayBackend.buildMenuInternal` — Duplicates `KSMacMenuBackend.buildMenu`

The tray backend adds a `static func buildMenuInternal` to `KSMacMenuBackend`
that is nearly identical to the instance method `buildMenu`. Could be refactored
to make `buildMenu` static or share an instance.

### 22. iOS/Android handler injection pattern — Consistent but under-documented

`KSiOSDialogBackend`, `KSAndroidDialogBackend`, `KSAndroidClipboardBackend`,
`KSAndroidShellBackend` use handler injection to bridge JVM/UIKit calls. The
pattern is well-designed but lacks documentation on **when** and **on which
actor** handlers should be set.

---

## 📋 Recommended Refactoring Priority

| Priority | Item | Impact |
|---|---|---|
| **P0** | iOS WindowBackend: implement actual UIWindow/WKWebView | iOS app non-functional |
| **P0** | iOS/Android MenuBackend: throw or implement | Debugging impossible |
| **P0** | iOS `create()`: create real UIWindow | iOS PAL useless |
| **P1** | `Result.unwrap()` → consolidate in KalsaeCore | Maintainability |
| **P1** | Linux `switch result` → `try result.unwrap()` | Code consistency |
| **P1** | `resolveModulePath()` deduplication | DRY violation |
| **P1** | Linux `runProcess`/`shell` deduplication | DRY violation |
| **P2** | macOS `saveFile` `beginSheetModal` fix | UX consistency |
| **P2** | Linux `Process.waitUntilExit` async wrapper | Thread efficiency |
| **P2** | Linux SingleInstance graceful shutdown | Stability |
| **P2** | iOS `canOpenURL`+`open` double call fix | Correctness |
| **P3** | Minimize `nonisolated(unsafe)` usage | Swift 6 safety |
| **P3** | Android `knownSchemes` thread safety | Safety |
| **P3** | iOS/Android handler injection documentation | Maintainability |

---

## Conclusion

**Windows and macOS PAL** maintain high quality with proper Swift 6 typed throws,
Sendable conformance, and actor isolation. **Linux PAL** is solid but has
consistency issues. **iOS and Android PAL** have critical gaps — particularly
iOS, where multiple protocol methods are no-ops that violate their contracts.
While mobile platforms are in preview status, even `unsupportedPlatform` throws
would be preferable to silent no-ops for debugging.
