# Plan: Minimize Kalsae Windows Package Output

Reduce `kalsae build` output from 6 files/dirs (`exe + exe.manifest + WebView2Loader.dll + Kalsae.json + Resources/ + kalsae.runtime.json`) toward a "near-single-file" deployment, in 3 incremental, low-risk phases. Skip the high-risk manifest-embedding step.

## Target end states

| Stage | Files in dist | Notes |
|---|---|---|
| **Today** | `App.exe` + `.manifest` + `WebView2Loader.dll` + `Kalsae.json` + `Resources/` + `kalsae.runtime.json` | 6 entries |
| **After A** | drop `WebView2Loader.dll` | static-link the loader |
| **After B** | drop `Resources/` | assets embedded via codegen |
| **After C** | drop `Kalsae.json` + `kalsae.runtime.json` | configs embedded via codegen |
| **Final** | `App.exe` + `App.exe.manifest` (+ optional icon, evergreen bootstrapper) | 2 essential files |

> Manifest is NOT removed. SwiftPM has no `.rc` compiler integration; the file is 1.5 KB and Win10/11 SxS lookup requires it. Embedding it is technically possible but high-risk and disproportionate to the savings.

> `webview2-runtime/` folder (fixed-runtime mode) is unchanged — Chromium binaries (200–500 MB) cannot be embedded.

---

## Phase A — Static-link WebView2Loader (quick win)

**Why first:** All three architectures (x64/arm64/x86) already ship `WebView2LoaderStatic.lib` in `Sources/CKalsaeWV2/Vendor/WebView2/build/native/`. The loader DLL is loaded dynamically only because [kswv2_loader.cpp](Sources/CKalsaeWV2/src/kswv2_loader.cpp) does so explicitly. Switching is a Package.swift + small C++ change.

**Steps**
1. **Add static link** — In [Package.swift](Package.swift) `CKalsaeWV2` target's `linkerSettings`, add `.linkedLibrary("WebView2LoaderStatic", .when(platforms: [.windows]))`. Also add `.unsafeFlags(["-L<path-to-arch>"])` per architecture (or use `#pragma comment(lib, ...)` in the C++ shim — preferred since it picks the right arch from `_M_*` macros).
2. **Replace dynamic dispatch** — In [kswv2_env.cpp](Sources/CKalsaeWV2/src/kswv2_env.cpp): replace `KSWV2_Loader_CreateEnvironmentWithOptions(...)` and `GetAvailableBrowserVersionString` with direct calls to `CreateCoreWebView2EnvironmentWithOptions` and `GetAvailableCoreWebView2BrowserVersionString` (the static lib exports them with the same signatures).
3. **Reduce the loader shim to a no-op** — Keep the file for ABI compatibility but make `KSWV2_Loader_SetDir` a no-op (return S_OK). Fixed-runtime is selected via `browserExecutableFolder` in the env options, NOT via SetDllDirectoryW; the SetDir was only used to find `WebView2Loader.dll` itself, which is no longer needed.
4. **Drop the DLL copy from packagers** — Remove `copyLoaderDLL(...)` call in [Packager.swift](Sources/KalsaeCLI/Support/Packager.swift) line ~140 and its helper. Also remove the WebView2Loader.dll warning paths.
5. **Tests** — Update [PackagerTests.swift](Tests/KalsaeCLITests/PackagerTests.swift) `loaderDLLIsStaged` and `loaderDLLMissingWarns` (now unused). Add a test asserting the packaged dir does NOT contain `WebView2Loader.dll`.
6. **Verify fixed-runtime still works** — Manual test (or fixture-based packager test): `kalsae build --webview2 fixed` still produces a working bundle. Static link does not affect fixed runtime: it's the env-option `browserExecutableFolder` that points at the runtime folder.

**Relevant files**
- [Package.swift](Package.swift) — add linker settings under platform gate
- [Sources/CKalsaeWV2/src/kswv2_loader.cpp](Sources/CKalsaeWV2/src/kswv2_loader.cpp) — gut the dynamic dispatch (or `#if 0` guard)
- [Sources/CKalsaeWV2/src/kswv2_env.cpp](Sources/CKalsaeWV2/src/kswv2_env.cpp) — call static symbols directly
- [Sources/KalsaeCLI/Support/Packager.swift](Sources/KalsaeCLI/Support/Packager.swift) — remove DLL copy
- [Tests/KalsaeCLITests/PackagerTests.swift](Tests/KalsaeCLITests/PackagerTests.swift) — adjust loader tests

**Verification**
1. `swift build` succeeds on Windows.
2. `swift test --filter "Packager"` passes.
3. Manual: `kalsae build` on the demo or test project produces a `dist/` without `WebView2Loader.dll`. The exe runs and the WebView loads.
4. Manual: `kalsae build --webview2 fixed` still ships `webview2-runtime/` and runs.
5. Confirm exe size grew by ~150–200 KB (the loader code is now inside).

**Decisions / scope**
- Keep `WebView2Loader.dll` artifact in `Vendor/` (Phase A doesn't delete vendor files).
- `KSWV2_Loader_SetDir` API is preserved as a no-op for ABI safety.

---

## Phase B — Embed frontend assets (biggest visual win)

**Why second:** Removes the entire `Resources/` folder, which is what makes the package look "messy" to users. `KSAssetResolver` is a struct with a single duck-typed `resolve(path:)` method — adding a parallel in-memory implementation is purely additive.

**Steps**
1. **Create `KSAssetResolver` protocol abstraction** — Convert today's struct to conform to a new `protocol KSAssetSource` (or similar). Existing struct becomes `KSDiskAssetResolver`. Keep the type alias / public name so call sites compile unchanged.
2. **Add `KSEmbeddedAssetResolver`** — In [Sources/KalsaeCore/Assets/](Sources/KalsaeCore/Assets/), new file. Backed by `[String: (Data, String /*MIME*/)]`. `resolve` does dictionary lookup.
3. **Add asset codegen** — New helper `KSAssetCodegen.run(distURL:, targetSwiftFile:)` in `Sources/KalsaeCLI/Support/`. Walks `dist/`, base64-encodes (or hex-encodes) each file, emits one Swift file with a `KSEmbeddedAssets.manifest: [String: [UInt8]]` constant + MIME map. Writes to `Sources/<UserTarget>/Generated/KSEmbeddedAssets.swift`.
4. **Wire codegen into `kalsae build`** — Add `--embed-assets` flag (default ON for release, OFF for `--debug`). When ON, run codegen BEFORE `swift build`; the user's target picks it up automatically since SwiftPM compiles every `.swift` under the target's path.
5. **Boot-time selection** — In `KSApp.boot`, if a generated `KSEmbeddedAssets` symbol is reachable (via a tiny conditional accessor / weak-import-style flag the codegen emits), prefer the embedded resolver; otherwise fall back to disk-based resolver. **Cleaner alternative:** the codegen also writes a tiny `_KSAssetsBootstrap.register()` call that the user's `App.swift` invokes — explicit but reliable.
6. **Skip Resources copy in packager** — When `--embed-assets` is in effect, packager skips the `Resources/` step.
7. **Tests** — New unit test for `KSEmbeddedAssetResolver.resolve` (round-trip a small fixture). Update Packager test fixture: when assets embedded, no `Resources/` directory in output.

**Considerations**
- **Source bloat**: A 5 MB SPA literal-encoded as Swift bytes can compile in seconds, but is awkward in `git` if committed. Recommendation: write to `.build/generated/` (untracked) and let `kalsae build` regenerate every release build. Tradeoff: re-builds every release. For dev, file-based resolver remains.
- **Compression**: Future enhancement — store gzip'd bytes, decompress on resolve. Skip in v1.
- **Hash invalidation**: Codegen should write a content hash header; if dist hasn't changed, skip rewrite to keep incremental SwiftPM builds fast.

**Relevant files**
- [Sources/KalsaeCore/Assets/KSAssetResolver.swift](Sources/KalsaeCore/Assets/KSAssetResolver.swift) — refactor to protocol
- New: `Sources/KalsaeCore/Assets/KSEmbeddedAssetResolver.swift`
- New: `Sources/KalsaeCLI/Support/AssetCodegen.swift`
- [Sources/KalsaeCLI/Commands/BuildCommand.swift](Sources/KalsaeCLI/Commands/BuildCommand.swift) — add `--embed-assets` flag, wire codegen
- [Sources/KalsaeCLI/Support/Packager.swift](Sources/KalsaeCLI/Support/Packager.swift) — skip Resources/ when embedded
- All 6 `KSAssetResolver(root:)` call sites — should be untouched if protocol abstraction is API-compatible
- New: `Tests/KalsaeCoreTests/KSEmbeddedAssetResolverTests.swift`

**Verification**
1. `swift test --filter "Asset"` covers both resolvers.
2. `kalsae build --embed-assets` on demo: output dir has no `Resources/` folder; exe runs; WebView shows index.html.
3. `kalsae build` (no flag, debug) still produces `Resources/` for back-compat dev path.
4. Codegen idempotency: running twice produces identical Swift output.

**Decisions / scope**
- Default: `--embed-assets` ON for release (`-c release` or `kalsae build` without `--debug`), OFF for debug.
- v1 stores raw bytes; gzip is deferred.
- Generated file path: `.build/generated/KSEmbeddedAssets.swift`, picked up via SwiftPM target source path or a sibling-target trick. (Sub-decision in implementation.)

---

## Phase C — Embed config files (cleanup)

**Why third:** Smallest savings (~5 KB total) but completes the "no JSON sidecars" picture. Easy after Phases A/B established codegen plumbing.

**Steps**
1. **Add `KSApp.boot(config: KSConfig, …)` overload** — Already nearly possible; [KSApp.swift](Sources/Kalsae/KSApp.swift) already has internal paths that take a parsed `KSConfig`. Just expose them publicly.
2. **Codegen `Kalsae.json` → `KSEmbeddedConfig.config: KSConfig`** — Same codegen pipeline; emit a Swift literal struct (or base64 of JSON, decoded once at startup; literal struct is faster but harder to keep in sync with `KSConfig` schema changes — JSON-then-decode is the safer choice).
3. **Codegen `kalsae.runtime.json` → embedded constant** — Same approach. Consumer at [KSWebView2Runtime.swift](Sources/KalsaePlatformWindows/WebView2/KSWebView2Runtime.swift); add an overload that accepts the policy struct directly instead of reading from disk.
4. **Update template `App.swift`** — When `--embed-assets` (extended to `--embed-all` or new `--embed-config`), call `KSApp.boot(config: KSEmbeddedConfig.config, ...)` and skip filesystem lookup.
5. **Skip JSON copy in packagers** — Both [Packager.swift](Sources/KalsaeCLI/Support/Packager.swift) and [PackagerMac.swift](Sources/KalsaeCLI/Support/PackagerMac.swift) skip `Kalsae.json` + `kalsae.runtime.json` when embedded.
6. **Tests** — Round-trip test: generated `KSEmbeddedConfig` decodes to the same `KSConfig` as the source JSON.

**Relevant files**
- [Sources/Kalsae/KSApp.swift](Sources/Kalsae/KSApp.swift) — public boot overload (mostly already exists)
- New: `Sources/KalsaeCLI/Support/ConfigCodegen.swift`
- [Sources/KalsaeCLI/Support/Templates/App.swift.tmpl](Sources/KalsaeCLI/Support/Templates/App.swift.tmpl) — branch on embed mode
- [Sources/KalsaePlatformWindows/WebView2/KSWebView2Runtime.swift](Sources/KalsaePlatformWindows/WebView2/KSWebView2Runtime.swift) — accept policy struct
- [Sources/KalsaeCLI/Support/Packager.swift](Sources/KalsaeCLI/Support/Packager.swift) + [PackagerMac.swift](Sources/KalsaeCLI/Support/PackagerMac.swift) — skip JSON copy when embedded

**Verification**
1. `swift test` passes including new config round-trip test.
2. `kalsae build --embed-all` on demo produces a dist with `App.exe + App.exe.manifest` only (plus icon if present).
3. The exe runs end-to-end.

---

## Out of scope (deliberate)

- **Manifest `.rc` embedding** — large effort, tiny payoff (1.5 KB). Defer indefinitely or treat as a separate RFC.
- **`webview2-runtime/` embedding** — physically impossible (Chromium binaries 200–500 MB; cannot be a valid Swift literal).
- **macOS / Linux equivalents** — Phase A is Windows-specific. Phases B/C generalize cleanly to those platforms (the resolver abstraction is cross-platform). Add to the same flags but verify on each PAL.
- **Compression** of embedded assets — Phase B+1 follow-up if exe size becomes a concern.

---

## Sequencing & dependencies

```
Phase A (static link)        ← independent, can ship first
       ↓
Phase B (embed assets)       ← independent of A, but bigger change. Establishes codegen pipeline.
       ↓
Phase C (embed config)       ← reuses Phase B's codegen pipeline. Trivial after B.
```

A and B can be done in parallel by separate developers if desired; C must follow B.

## Risks / decisions to confirm before implementation

1. **Static-link fixed-runtime sanity check** — Confirm by code-reading `WebView2LoaderStatic.lib` interface (pdb / dumpbin) that `browserExecutableFolder` env-option is honored when statically linked. (Microsoft docs say yes; verify before merging Phase A.)
2. **`--embed-assets` default in release builds** — User feedback: should this be ON by default or opt-in? Recommend ON for release, OFF for debug. Confirm with user.
3. **Source vs. file-system codegen output location** — `.build/generated/` is invisible to user but requires SwiftPM target coercion to compile it. `Sources/<Target>/Generated/` is conventional but pollutes user repo. Recommend `.build/generated/` with a tiny SwiftPM sibling target.
