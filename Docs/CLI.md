# Kalsae CLI Reference

## Overview

The `kalsae` CLI provides project scaffolding, development, building, packaging, and code generation tools for Kalsae applications.

## Installation

The CLI is built as part of the Kalsae package:

```bash
# Build the CLI
swift build --product kalsae

# Run directly
swift run kalsae --help
```

## Commands

### `kalsae new <name>`

Scaffold a new Kalsae application project.

```bash
kalsae new my-app
kalsae new -n my-app -d ./projects/my-app -g --ide vscode
kalsae new --list
kalsae new my-app --frontend react --package-manager pnpm
```

Creates the following directory structure:

```
my-app/
├── Package.swift
└── Sources/my-app/
    ├── App.swift
    └── Resources/
        ├── Kalsae.json
        └── index.html
```

**Arguments:**

| Argument | Description |
|---|---|
| `name` | Application name (used as directory, target, and window title). Must start with a letter and contain only letters, digits, hyphens, or underscores. Optional when `--name` is given or `--list` is used. |

**Options (Wails-compatible aliases):**

| Option | Description |
|---|---|
| `-n, --name <name>` | Application name. Alias for the positional argument. Specifying both is an error. |
| `-d, --dir <path>` | Output directory (default: `./<name>`). |
| `-g, --git` | Initialise a Git repository in the new project (`git init` + initial commit). Skipped with a warning when `git` is unavailable. |
| `-l, --list` | List available frontend presets and exit. |
| `-q, --quiet` | Suppress progress output (errors and the final tree are still printed). |
| `-f, --force` | Overwrite the destination directory if it already exists. |
| `--ide <kind>` | Generate IDE configuration files. Supported: `vscode` (creates `.vscode/settings.json` + `.vscode/launch.json`). |
| `--frontend <preset>` | Frontend preset: `vanilla` (default) \| `react` \| `vue` \| `svelte`. |
| `--package-manager <pm>` | Package manager for dev/build commands: `npm` (default) \| `pnpm` \| `yarn`. |
| `--kalsae-path <path>` | Use a local Kalsae checkout as a SwiftPM path dependency instead of fetching from GitHub. |
| `--no-install` | Skip running `npm install` after scaffolding (non-vanilla frontends only). |
| `--use-external-scaffolder` | Use `npm create vite@latest` instead of bundled templates (react/vue/svelte). Requires Node.js + npm. |

### `kalsae dev`

Run the project in development mode.

When `Kalsae.json` includes `build.devCommand`, the CLI starts that command first
(for example `npm run dev`). By default, if `build.devServerURL` is an HTTP(S)
URL, `kalsae dev` waits until the server is reachable before launching
`swift run`.

```bash
kalsae dev
kalsae dev --target my-app
kalsae dev --browser --app-args "--debug"
kalsae dev --frontend-dev-server-url http://localhost:5173 --dev-server-timeout 30
kalsae dev --no-reload    # disable dev live-reload
```

**Options:**

| Option | Description |
|---|---|
| `-t, --target <target>` | Executable target to run (required when `Package.swift` has multiple executables). |
| `--config <path>` | Override path to `Kalsae.json` (default: `./Kalsae.json` or `./kalsae.json` when present). |
| `--skip-dev-command` | Do not launch `build.devCommand` even when configured. |
| `--no-wait-dev-server` | Skip readiness check for `build.devServerURL`. |
| `--watch` | Watch `Sources/` and restart `swift run` on file changes. |
| `--watch-interval <seconds>` | Polling interval for `--watch` mode. Default: `1.0`. |
| `--debounce <ms>` | Minimum milliseconds between watch-mode restarts (debounces rapid file changes). Default: `200`. |
| `--browser` | Open `build.devServerURL` (or `--frontend-dev-server-url`) in the default browser once it is reachable. |
| `--app-args "..."` | Arguments appended after `swift run <target> --` (shell-quoted). |
| `--frontend-dev-server-url <url>` | Override `build.devServerURL` from the config (Wails: `-frontenddevserverurl`). |
| `--dev-server-timeout <seconds>` | Seconds to wait for the dev server to become reachable. Default: `20`. |
| `--reload` / `--no-reload` | Set `KALSAE_DEV_RELOAD=1` in the launched app's environment so the host can opt into dev live asset reload. Default: `--reload`. |
| `--no-auto-fetch-web-view2` | Disable automatic fetching of the WebView2 SDK on Windows. |
| `--webview2-sdk-version <ver>` | WebView2 SDK version when auto-fetching (default: `latest`). |

This command runs `swift run [target]` under the hood and cleans up the spawned
dev command process when `swift run` exits.

#### Dev live asset reload (`--reload`)

When `--reload` is in effect (the default), `kalsae dev` exports
`KALSAE_DEV_RELOAD=1` to the launched application. The host runtime
(`KSApp.boot`) detects this environment variable and — only when assets are
served from a local directory through the virtual host (`https://app.kalsae/`
on Windows / `ks://app/` on macOS / Linux) — starts a `KSAssetWatcher` that
polls the resolved frontend dist directory and triggers `webview.reload()`
when files change. Use `--no-reload` to disable it (e.g. when an external
dev server already provides HMR).

### `kalsae build`

Build the project for release (or debug).

When `Kalsae.json` includes `build.buildCommand`, the CLI runs that command
before `swift build` (for example `npm run build`). By default, `kalsae build`
also validates that frontend dist exists and is not empty. By default it syncs
frontend dist into `Sources/<target>/Resources` before `swift build`.

**Packaging is enabled by default** (Wails-compatible). Use `--no-package` to
skip packaging.

```bash
kalsae build                       # Release build + package (default)
kalsae build --no-package          # Release build only
kalsae build --debug               # Debug build
kalsae build --clean --dryrun      # Preview commands after cleaning .build/
kalsae build --target my-app -o my-app-x64
kalsae build --nsis                # Windows: also produce NSIS installer
kalsae build --signtool-cmd "signtool sign /a /fd SHA256 {file}" \
             --nsis --nsis-signtool-cmd "signtool sign /a /fd SHA256 {file}"
```

**Options:**

| Option | Description |
|---|---|
| `-d, --debug` | Build in debug configuration instead of release. |
| `-t, --target <target>` | Executable target to build. |
| `--package` / `--no-package` | Produce a redistributable package after building. **Default: ON** (Wails-compatible). Use `--no-package` to skip. |
| `--webview2 <policy>` | WebView2 runtime distribution policy: `evergreen` (default), `fixed`, or `auto`. |
| `--arch <arch>` | Target architecture. Windows: `x64` (default) \| `arm64` \| `x86`. macOS: `arm64` \| `x86_64` \| `universal`. |
| `--bootstrapper <path>` | Path to `MicrosoftEdgeWebview2Setup.exe` (Evergreen bootstrapper). |
| `--config <path>` | Override path to `Kalsae.json`. |
| `--dist <path>` | Override frontend dist directory. |
| `--allow-missing-dist` | Allow build to continue even if frontend dist is missing or empty. |
| `--no-sync-resources` | Skip syncing frontend dist into `Sources/<target>/Resources`. |
| `--icon <path>` | Override icon path (`.ico` on Windows). |
| `--zip` | Produce a portable `.zip` alongside the package directory. |
| `--output <path>` | Override package output directory. |
| `--clean` | Remove `.build/` and the package output directory before building. |
| `--skip-frontend` | Skip running `build.buildCommand` (frontend build step). |
| `--dryrun` | Print the build/package commands without executing them. |
| `-o, --exe-name <name>` | Override the produced executable name (renames the binary in `.build/<config>/` after `swift build`). |
| `--nsis` | Windows: generate an NSIS installer (`.nsi` script + `makensis`-compiled `.exe`) after packaging. Skipped with a warning if `makensis` is not on PATH. |
| `--nsis-publisher <name>` | Hint passed to the NSIS template Publisher field (default: `app.identifier`). |
| `--signtool-cmd "<template>"` | Windows: codesign the packaged executable. The template runs through the host shell. Use `{file}` as a placeholder for the absolute exe path; if omitted, the path is appended automatically. Honors `--dryrun` (printed only). |
| `--nsis-signtool-cmd "<template>"` | Windows: codesign the NSIS installer after `makensis`. Same template syntax as `--signtool-cmd`. Requires `--nsis`. |
| `--no-auto-fetch-web-view2` | Disable automatic fetching of the WebView2 SDK on Windows. |
| `--webview2-sdk-version <ver>` | WebView2 SDK version when auto-fetching. |

#### Packaging

The packager (`KSPackager`) creates a redistributable folder containing the
built executable, frontend dist, runtime, and `Kalsae.json`. Optionally it
also produces a `.zip` archive (`--zip`).

**Windows** (`KSPackager.run`):

- **WebView2 policies**:
  - `evergreen` — Ships the Evergreen bootstrapper (users get auto-updates).
  - `fixed` — Bundles a specific WebView2 version from `Vendor/WebView2/`.
  - `auto` — Tries fixed first, falls back to evergreen.
- Architecture-specific runtime folders for WebView2.
- Icon embedding (`.ico`).

**Windows installer (`--nsis`)**:

- `KSNSISTemplate` renders an `.nsi` script (Install/Uninstall sections,
  Start Menu + Desktop shortcuts, uninstaller registry keys, optional
  silent WebView2 bootstrapper invocation).
- `KSPackager.runNSIS` invokes `makensis /V2`. When `makensis` is not on
  PATH, the script is still emitted and a warning is printed.

**macOS** (`KSPackager.runMacOS`):

- Produces a `<App>.app` bundle: `Contents/{MacOS, Resources, Info.plist}`.
- `Info.plist` keys: `CFBundleIdentifier`, `CFBundleName`, `CFBundleVersion`,
  `CFBundleExecutable`, `LSMinimumSystemVersion`, etc.
- `--arch universal` is supported when `lipo` is available.

**Code signing (Windows)**:

- `--signtool-cmd` runs **before** NSIS so the installer packages an already-signed binary.
- `--nsis-signtool-cmd` runs **after** `makensis` to sign the installer itself.
- Both honor `--dryrun` (prints the rendered command but does not execute).
- Certificate / key management is the user's responsibility; these flags are
  thin shell hooks. Use `{file}` to control where the absolute path is
  inserted in your template.

### `kalsae version`

Print the CLI version. Equivalent to `kalsae --version`.

```bash
kalsae version
```

### `kalsae generate bindings`

Generate TypeScript type definitions for `@KSCommand` functions.

```bash
kalsae generate bindings
kalsae generate bindings -o src/lib/kalsae.gen.ts
kalsae generate bindings --module MyApp
kalsae generate bindings Sources/MyApp/Commands.swift
```

**Options:**

| Option | Description |
|---|---|
| `-o, --out <path>` | Output `.ts` file path. Defaults to `<project>/src/lib/kalsae.gen.ts`. |
| `--project <path>` | Project root containing `Sources/`. Defaults to CWD. |
| `--module <name>` | Module name embedded in the generated header. Default: `Kalsae`. |
| `inputs` | Optional explicit Swift source files or directories. |

The bindings generator (`KSBindingsGenerator`):

1. Discovers Swift source files (recursively from `Sources/` or explicit paths).
2. Parses `@KSCommand` macro annotations using SwiftSyntax.
3. Generates a TypeScript file with typed `invoke()` wrappers and event listeners.

**Example output:**

```typescript
// Auto-generated by Kalsae Bindings Generator
// Module: MyApp

/**
 * Greet the user.
 * @KSCommand
 */
export async function greet(name: string): Promise<{ greeting: string }> {
  return __KS_.invoke("greet", { name });
}
```

### `kalsae doctor`

Check common environment and project issues.

```bash
kalsae doctor
kalsae doctor --strict
kalsae doctor --json
```

**Options:**

| Option | Description |
|---|---|
| `--config <path>` | Override path to `Kalsae.json` (default: `./Kalsae.json` or `./kalsae.json`). |
| `--strict` | Exit with non-zero status when warnings are found. |
| `--json` | Print machine-readable JSON output. |

Current checks include:

1. Config file discovery and decode.
2. Frontend dist existence and non-empty state.
3. WebView2 static loader availability on Windows.
4. swift-syntax cache shape under `.build/repositories`.

When swift-syntax cache looks unhealthy, doctor prints these recovery commands:

```powershell
Remove-Item -Recurse -Force .build\repositories\swift-syntax-*
swift package resolve --disable-dependency-cache
```

## Configuration File

The CLI looks for `Kalsae.json` (or `kalsae.json`) in the project root directory. See `Examples/kalsae.sample.json` for a complete reference.

## Shell Rules (Windows)

When using the CLI on Windows:

- Use PowerShell 5.1 or 7.
- Chain commands with `;` — **never** `&&`.
- Working directory should be the project root.
- For WebView2 setup, use `Scripts/fetch-webview2.ps1`. When installing into a
  different consumer project root, pass `-ProjectRoot <path>`.
- Use `-DryRun` to verify computed install paths without network/download.
- For a quick path-resolution check, run `Scripts/smoke-fetch-webview2.ps1`.

## Exit Codes

| Code | Description |
|---|---|
| `0` | Success |
| `1` | General error (validation, build failure, etc.) |
