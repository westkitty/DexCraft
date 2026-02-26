# DexCraft

DexCraft is a macOS SwiftUI prompt workbench for turning rough input into cleaner, stronger prompts with offline-first processing.

## What It Does

- Enhances and restructures rough prompts into production-ready output.
- Uses an embedded tiny local model (llama.cpp runtime) when available.
- Falls back to deterministic heuristics when local model output is invalid.
- Provides a detached main panel and a dedicated local-chat pop-out window.
- Tracks quality gates, optimized preview, history, library, and templates.

## Current Core Behaviors

- `Forge Prompt` always attempts a meaningful enhancement path.
- If tiny/fallback output is empty or near-duplicate, DexCraft applies a validated compiled fallback result.
- Local chat pop-out can discuss prompt ideas and inject messages back into rough input (`Use as Rough Input` and `Use + Forge`).

## Requirements

- macOS with Xcode command line tools.
- Xcode project: `DexCraft.xcodeproj`
- Embedded tiny runtime binaries are expected under:
  - `Tools/embedded-tiny-runtime/macos-arm64`

## Build / Install

```bash
./install_app.sh
```

This builds Release and installs to:

- `/Applications/DexCraft.app`

## Run Tests

```bash
xcodebuild -project DexCraft.xcodeproj -scheme DexCraft -destination 'platform=macOS' test
```

## Launch App

```bash
open /Applications/DexCraft.app
```

## Repository Notes

- Remote: `https://github.com/westkitty/DexCraft.git`
- Default branch: `master`
- If GitHub looks empty, verify you are viewing the `master` branch.
