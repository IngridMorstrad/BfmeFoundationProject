# App bundle assets

This directory holds the Apple-specific bundle metadata and icon assets for
`BfmeLauncherApp`.

## AppIcon

`AppIcon.iconset/` contains every PNG variant Apple's `iconutil` needs to
build a `.icns`. The PNGs are generated from
`src/BfmeFoundationProject_AllInOneLauncher/allinonelaunchericon.ico` by
extracting its 128x128 frame (the only size stored in the source `.ico`) and
resampling it to the standard iconset sizes.

To build the final `.icns` on a Mac (Apple Silicon or Intel):

```bash
iconutil -c icns mac/App/AppIcon.iconset
# produces mac/App/AppIcon.icns
```

`iconutil` ships with Xcode's command-line tools and is not available on
Linux, so the `.icns` is generated at packaging time on a Mac host.

## Info.plist

The bundle's `Info.plist` references the generated `AppIcon` resource via
`CFBundleIconFile`/`CFBundleIconName`. When assembling the `.app` bundle on
a Mac, place `AppIcon.icns` next to this plist inside `Contents/Resources`.
