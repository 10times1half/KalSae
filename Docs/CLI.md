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
| `name` | Application name (used as directory, target, and window title). Must start with a letter and contain only letters, digits, hyphens, or underscores. |

### `kalsae dev`

Run the project in development mode.

When `Kalsae.json` includes `build.devCommand`, the CLI starts that command first
(for example `npm run dev`). By default, if `build.devServerURL` is an HTTP(S)
URL, `kalsae dev` waits until the server is reachable before launching
`swift run`.

```bash
kalsae dev
kalsae dev --target my-app
```

**Options:**

| Option | Description |
|---|---|
| `-t, --target <target>` | Executable target to run (required when `Package.swift` has multiple executables). |
| `--config <path>` | Override path to `Kalsae.json` (default: `./Kalsae.json` or `./kalsae.json` when present). |
| `--skip-dev-command` | Do not launch `build.devCommand` even when configured. |
| `--no-wait-dev-server` | Skip readiness check for `build.devServerURL`. |
| `--watch` | Watch `Sources/` and restart `swift run` on changes. |
| `--watch-interval <seconds>` | Polling interval for `--watch` mode. Default: `1.0`. |

This command runs `swift run [target]` under the hood and cleans up the spawned
dev command process when `swift run` exits.

### `kalsae build`

Build the project for release (or debug).

When `Kalsae.json` includes `build.buildCommand`, the CLI runs that command
before `swift build` (for example `npm run build`). By default, `kalsae build`
also validates that frontend dist exists and is not empty. By default it syncs
frontend dist into `Sources/<target>/Resources` before `swift build`.

```bash
kalsae build                    # Release build
kalsae build --debug            # Debug build
kalsae build --target my-app    # Specific target
```

**Options:**

| Option | Description |
|---|---|
| `-d, --debug` | Build in debug configuration instead of release. |
| `-t, --target <target>` | Executable target to build. |
| `--package` | Produce a redistributable package after building. |
| `--webview2 <policy>` | WebView2 runtime distribution policy: `evergreen` (default), `fixed`, or `auto`. |
| `--arch <arch>` | Target architecture: `x64` (default), `arm64`, or `x86`. |
| `--bootstrapper <path>` | Path to `MicrosoftEdgeWebview2Setup.exe` (Evergreen bootstrapper). |
| `--config <path>` | Override path to `Kalsae.json` (default: `./Kalsae.json` or `./kalsae.json`). |
| `--dist <path>` | Override frontend dist directory. |
| `--allow-missing-dist` | Allow build to continue even if frontend dist is missing or empty. |
| `--no-sync-resources` | Skip syncing frontend dist into `Sources/<target>/Resources`. |
| `--icon <path>` | Override icon path (`.ico`). |
| `--zip` | Produce a portable `.zip` alongside the package directory. |
| `--output <path>` | Override package output directory. |

#### Packaging (`--package`)

When `--package` is specified, the build command also creates a redistributable package:

1. Builds the Swift executable.
2. Loads `Kalsae.json` for app metadata.
3. Copies the executable, frontend dist, WebView2 runtime, and config into an output directory.
4. Optionally creates a `.zip` archive (`--zip`).

The packager (`KSPackager`) handles:

- **WebView2 policies**:
  - `evergreen` — Ships the Evergreen bootstrapper (users get auto-updates).
  - `fixed` — Bundles a specific WebView2 version from `Vendor/WebView2/`.
  - `auto` — Tries fixed first, falls back to evergreen.
- **Architecture-specific runtime folders** for WebView2.
- **Icon embedding** (Windows `.ico`).
- **Config bundling** — `Kalsae.json` is included in the package.

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
