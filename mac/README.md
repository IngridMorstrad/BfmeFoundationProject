# BFME Workshop — macOS native rewrite

This directory contains a native macOS (Apple Silicon) rewrite of the
Windows-only .NET/WPF BFME Workshop launcher. The original C# tree under
`../src/` is preserved unchanged so the Windows build continues to work.

## Layout

```
mac/
├── Package.swift                       SwiftPM workspace manifest
├── Sources/
│   ├── CZlib/                          system zlib module map
│   ├── BfmeHttpInstruments/            URLSession HTTP client port
│   ├── BfmeKitCore/                    portable data + logic cores
│   │   ├── Data/                       POCO ports (RGBA, BfmeMap, ...)
│   │   ├── IO/                         BIG archive, TGA, CSF decoders
│   │   └── Utils/                      BinaryReader, FilenameUtils, RectUtils
│   ├── BfmeDirectXRuntime/             Wine-prefix DX9 redist extractor
│   ├── BfmeKit/                        umbrella re-export of BfmeKitCore
│   ├── BfmeWorkshopKit/                placeholder, filled in a later feature
│   ├── BfmeOnlineKit/                  placeholder, filled in a later feature
│   ├── BfmeOnlineKitUI/                placeholder (macOS-only UI later)
│   └── BfmeLauncherApp/                executable entry point (scaffold)
└── Tests/
    ├── BfmeHttpInstrumentsTests/
    ├── BfmeKitCoreTests/
    └── BfmeDirectXRuntimeTests/
```

## Building

```sh
swift build --package-path mac
swift test  --package-path mac
```

Swift 6.x is required. The portable subset of the rewrite compiles on both
macOS and Linux; macOS-only SwiftUI/AppKit targets are added in later
features and gated with `.when(platforms: [.macOS])`.
