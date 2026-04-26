# GitHub Copilot Instructions

The full agent guide for this repository lives in [AGENTS.md](../AGENTS.md).
Read it first.

## Quick reference (do not deviate without checking AGENTS.md)

- Swift 6.0, swift-tools-version 6.0, language mode v6.
- Tests use **swift-testing** (`@Test`, `@Suite`, `#expect`). **Not XCTest.**
- PowerShell on Windows: chain with `;`, never `&&`.
- Build: `swift build` · Test: `swift test` · Filter: `swift test --filter "name"`.
- Windows setup: run `./Scripts/fetch-webview2.ps1` once before building.
- Linux setup: `apt install libgtk-4-dev libwebkitgtk-6.0-dev libsoup-3.0-dev`.

## Hard rules

- Don't refactor or reformat code unrelated to the task.
- Don't add doc comments / annotations to code you didn't change.
- Don't create new markdown files unless explicitly asked.
- Don't use `internal import` in files that expose `public` types.
- Don't add force unwraps (`!`) or `try!` in production code.
- Use typed throws (`throws(KSError)`) and prefer bare `catch`.

See [AGENTS.md](../AGENTS.md) §7 (Don'ts) for the full list and rationale.
