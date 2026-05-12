# BFME Workshop — macOS (Apple Silicon) native rewrite

This directory contains a native macOS rewrite of the Windows-only
.NET / WPF BFME Workshop launcher and its support libraries. The
original C# tree under `../src/` is preserved unchanged so the Windows
build continues to work; nothing in `mac/` modifies or depends on it.

The launcher itself is 100 % native Swift 6 / SwiftUI / AppKit and
builds to a single-file `arm64` binary. There is no Rosetta and no
Mono / .NET runtime involved.

## Prerequisites

* **macOS 14 Sonoma or later** (macOS 15 Sequoia is also supported).
* **Apple Silicon** — M1, M2, M3 or M4. Intel Macs are not supported;
  the output is arm64-only by design.
* Either
  * **Xcode 16+** (ships with the Swift 6 toolchain), or
  * a standalone **Swift 6.x toolchain** from
    [https://swift.org/download](https://swift.org/download).

No Homebrew or extra package managers are required to build the
launcher; `zlib` ships with macOS.

## Building and testing

From the repository root:

```sh
# Release build (arm64 binary, optimised)
swift build -c release --package-path mac

# Run the full XCTest suite (90 tests at the time of writing)
swift test --package-path mac
```

The release binary is written to
`mac/.build/release/BfmeLauncherApp` and can be run directly from the
terminal or wrapped into an `.app` bundle (see "Packaging" below).

### Open in Xcode

SwiftPM manifests open natively in Xcode:

```sh
open mac/Package.swift
```

Xcode will resolve the manifest, show every module under the project
navigator and let you run / debug the `BfmeLauncherApp` scheme on your
local Mac.

## Architecture

Each original `src/BfmeFoundationProject_*` .NET project is mirrored by
one Swift module under `mac/Sources/`. The module names stay close to
the originals so a C# reader can navigate the Swift tree easily.

| Original .NET project                           | Swift module(s) under `mac/Sources/`         | Notes                                                                             |
| ----------------------------------------------- | -------------------------------------------- | --------------------------------------------------------------------------------- |
| `BfmeFoundationProject_BfmeKit`                 | `BfmeKitCore`, `BfmeKit`                     | Portable data + IO core (BIG, TGA, CSF, registry shim) plus the manager umbrella. |
| `BfmeFoundationProject_HttpInstruments`         | `BfmeHttpInstruments`                        | URLSession port of the C# `HttpMarshal` + gzip via `CZlib`.                       |
| `BfmeFoundationProject_WorkshopKit`             | `BfmeWorkshopKit`                            | Workshop auth, query, download, library and sync managers.                        |
| `BfmeFoundationProject_OnlineKit`               | `BfmeOnlineKit`, `BfmeOnlineKitUI`           | Arena helpers (pure logic) + SwiftUI surface (macOS-only).                        |
| `BfmeFoundationProject_DirectXRuntime`          | `BfmeDirectXRuntime`                         | Extracts the bundled DX9 redist into the selected Wine prefix.                    |
| `BfmeFoundationProject_AllInOneLauncher` (WPF)  | `BfmeLauncherApp`                            | SwiftUI app shell, pages, popups, `@Observable` `AppState`.                       |
| (system dep: `System.IO.Compression`)           | `CZlib`                                      | `systemLibrary` module map over the system `zlib`.                                |

Ports follow the original organisation deliberately: every manager
(`BfmeRegistryManager`, `BfmeLaunchManager`, `BfmeSyncManager`,
`BfmeWorkshopManager`, etc.) exists as a Swift `enum` with the same
public surface, and each original WPF `Page` has a matching SwiftUI
`View`. The WPF `PopupVisualizer` overlay pattern is replicated by an
`@Observable AppState` + `PopupHost` pair.

## Running BFME itself (Wine / CrossOver / Whisky / GPTK)

The launcher is native macOS, but **Battle for Middle-earth is still a
Windows-only game**. To actually launch and play BFME you need a
Windows compatibility layer installed on your Mac. The launcher is
aware of this and talks to the chosen prefix via the standard Wine
layout.

The launcher has been designed to work with any of the following:

* **Whisky** — easiest path on Apple Silicon. Install from
  [https://getwhisky.app](https://getwhisky.app), create a new bottle
  (Windows 10, Apple GPTK 2 backend), and point the launcher at it via
  `Settings → Wine prefix`.
* **CrossOver 24+** — create a Windows 10 bottle, install BFME into
  it, then point the launcher at
  `~/Library/Application Support/CrossOver/Bottles/<name>`.
* **Apple Game Porting Toolkit (GPTK) 2** — build your own Wine from
  Apple's distribution and set `WINEPREFIX` to point the launcher at
  it. Recommended only if you are already comfortable with GPTK.
* **Stock Wine / wine-crossover from Homebrew** — works, but D3D9
  performance will be noticeably worse than any of the above.

The `BfmeDirectXRuntime` module drops `d3dx9_*.dll`, `msvcr*.dll` and
friends into the prefix's `drive_c/windows/system32` folder so that
BFME's DirectX 9 dependencies are satisfied inside the bottle.
Everything else (registry shim, launch, sync, Workshop) goes through
the same prefix.

## Apple Silicon specifics

* The produced binary is **arm64** (`file BfmeLauncherApp` reports
  `Mach-O 64-bit executable arm64`). No Rosetta required.
* The launcher is a single static binary plus a `Resources` bundle; it
  does not require installing a .NET runtime, WPF, Mono, or any other
  framework beyond what ships with macOS 14.
* Use of `NSStatusItem`, `NSOpenPanel`, `NSWorkspace` and SwiftUI's
  `Scene` / `WindowGroup` is gated behind `#if canImport(SwiftUI)` so
  the portable library subset also builds on Linux CI (see below).

## Packaging (.app bundle and .icns)

The SwiftPM target produces a plain executable. To assemble a
distributable `.app` bundle, wrap the release binary together with
`App/Info.plist` and a generated `.icns`:

```sh
# 1. Release build
swift build -c release --package-path mac

# 2. Generate the .icns from the iconset at packaging time
iconutil -c icns mac/App/AppIcon.iconset

# 3. Assemble the bundle
APP=mac/.build/release/BfmeLauncher.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp mac/.build/release/BfmeLauncherApp "$APP/Contents/MacOS/BfmeLauncher"
cp mac/App/Info.plist                 "$APP/Contents/Info.plist"
cp mac/App/AppIcon.icns               "$APP/Contents/Resources/AppIcon.icns"
```

`iconutil` is part of the macOS command-line tools and is not
available on Linux, which is why the `.icns` is generated at packaging
time rather than checked in.

For distribution outside the App Store, you'll then want to codesign
and notarise the bundle with your Developer ID — that step is
deliberately left to the maintainer.

## What is verified on CI vs what requires a real Mac

There are two CI workflows in this repo under `.github/workflows/`:

* **`linux-swift.yml`** — runs on `ubuntu-latest` with Swift 6.0 and
  executes `swift build --package-path mac` and
  `swift test --package-path mac`. This validates the portable subset
  on every push: `BfmeKitCore`, `BfmeHttpInstruments`,
  `BfmeDirectXRuntime` (non-UI extraction logic), `BfmeKit`,
  `BfmeWorkshopKit`, `BfmeOnlineKit` (models + helpers) and all of
  their XCTest targets. SwiftUI / AppKit code paths compile as empty
  stubs on Linux, so any pure-logic regression is caught here in
  under a minute.

* **`macos.yml`** — runs on `macos-14` (Apple Silicon GitHub runner)
  and executes `swift build -c release --package-path mac` followed
  by `swift test --package-path mac`. This is the only job that
  exercises the full SwiftUI / AppKit surface and the
  `BfmeLauncherApp` executable target. The release binary is
  uploaded as a workflow artifact so reviewers can download and run
  it without needing the Swift toolchain.

| What                                                 | Linux CI (Ubuntu) | macOS CI (M-series) |
| ---------------------------------------------------- | ----------------- | ------------------- |
| `BfmeKitCore` logic + unit tests                     | ✅                 | ✅                   |
| `BfmeHttpInstruments` + gzip                         | ✅                 | ✅                   |
| `BfmeDirectXRuntime` extractor + tests               | ✅                 | ✅                   |
| `BfmeWorkshopKit` + `BfmeOnlineKit` logic            | ✅                 | ✅                   |
| SwiftUI views, `@Observable AppState`, popup host    | ❌ (stubbed out)   | ✅                   |
| `BfmeLauncherApp` executable link                    | ❌                 | ✅                   |
| Launching BFME through a Wine prefix                 | ❌                 | Manual on a real M-series Mac |
| `.app` bundle + `iconutil -c icns` packaging         | ❌                 | Manual (see above)  |

In short: everything that doesn't need AppKit is fully covered on both
platforms; anything that does need AppKit is covered on the macOS
runner; and actually launching BFME still requires a real Mac with a
Wine / CrossOver / Whisky / GPTK prefix installed.
