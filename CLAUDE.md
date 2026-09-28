# SelectTranslate — notes for Claude Code

macOS menu-bar-only app (Swift Package, SwiftUI + AppKit, macOS 13+). Selecting text in any app shows a floating button; clicking it sends the text to the Claude Messages API (streaming) to translate into Vietnamese and suggest 3 replies in the source language.

## Commands
- `make build` — compile only (`swift build`). Run this first after any change.
- `make run` — build, package `build/SelectTranslate.app` (scripts/build-app.sh), ad-hoc sign, open.
- `make install` — copy to /Applications.
- `make reset-ax` — reset Accessibility permission (needed after ad-hoc rebuilds).

## Architecture
- `SelectTranslateApp.swift`: `MenuBarExtra(.window)` → `SettingsView`; `AppDelegate` wires `SelectionMonitor` → `PopupController`, registers ⌥D `HotKey`.
- Selection: global `NSEvent` monitors (mouse down/up, Esc). On drag > 6px or multi-click, `SelectionReader` reads `kAXSelectedTextAttribute`; if AX is unsupported it simulates ⌘C and restores the clipboard.
- UI: `FloatingPanel` = borderless `.nonactivatingPanel` at `.popUpMenu` level so the source app keeps focus. `FirstMouseHostingView` makes first click work.
- Claude: `ClaudeClient.stream` parses SSE `content_block_delta`. Prompt asks for a tagged format (`<lang>`, `<translation>`, `<reply><tone><text><meaning>`) that `ResponseParser` parses incrementally while streaming.
- Two providers (`AppSettings.provider`): `.apiKey` → `ClaudeClient` (HTTP SSE); `.claudeCode` → `ClaudeCodeClient` runs `claude -p --output-format stream-json --verbose --include-partial-messages --system-prompt … --max-turns 1` in a temp dir, strips `ANTHROPIC_API_KEY` so the logged-in Pro/Max account is used, and resolves PATH via login shell (GUI apps lack terminal PATH; nvm installs need node on PATH).
- Settings in UserDefaults; API key in Keychain (env `ANTHROPIC_API_KEY` as fallback).

## Constraints
- Swift 5 language mode (tools 5.9); classes are intentionally not `@MainActor`-annotated. Everything UI runs on main via AppKit callbacks / `DispatchQueue.main` / `Task { @MainActor in }`.
- No App Sandbox (Accessibility + CGEvent posting need it off). Distribute as signed + notarized DMG, not App Store.
- The initial scaffold was written without compiling on a Mac — if `make build` fails, fix the compile errors first.

## Ideas / TODO
- Use `kAXBoundsForRangeParameterizedAttribute` to anchor the button to the selection instead of the mouse.
- Configurable hotkey; "insert reply" into the source app; pin popup; history persistence.
