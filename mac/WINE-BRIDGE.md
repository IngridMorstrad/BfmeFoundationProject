# The Wine bridge, and where the native rewrite has to stop

## Where the floor is

The rewrite under `mac/` makes the launcher native. It cannot make *the games*
native, and that is not a question of effort:

- **The BFME source code is not available and will not be.** EA released
  Command & Conquer: Generals and Zero Hour under GPLv3 in February 2025
  ([EA](https://github.com/electronicarts/CnC_Generals_Zero_Hour)), and those
  share SAGE ancestry with BFME. BFME itself was excluded. The Lord of the Rings
  licence sits with Warner, not EA, which is why EA cannot re-release or
  re-license these titles at all.
- **No open-source BFME engine is playable.** OpenSAGE can load SAGE assets,
  maps and UI, but its own project page describes gameplay as largely
  unimplemented ([OpenSAGE](https://opensage.github.io/)). OpenBFME describes
  itself as early prototype groundwork.

So `lotrbfme.exe`, `lotrbfme2.exe` and `lotrbfme2ep1.exe` stay as they are:
closed-source, 32-bit, Direct3D 9 Windows binaries from 2004-2006. They run
under Wine (Whisky, CrossOver, GPTK, stock Wine). Everything above them —
launcher UI, Workshop, patch management, sync — is native Swift.

That makes the boundary between the two the most important thing in this
codebase, and `BfmeWineBridge` is that boundary.

## The problem this module solves

The games find themselves through the Windows registry. On startup each one
reads:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Electronic Arts\...\<title>
    InstallPath        REG_SZ     where the game lives
    Language           REG_SZ
    UserDataLeafName   REG_SZ     which %APPDATA% folder holds Options.ini
    Version            REG_DWORD
```

Under Wine that read resolves to the **prefix's** registry (`system.reg`). State
the launcher keeps anywhere else — a JSON file under
`~/Library/Application Support`, say — is invisible to the game, and the game
concludes it is not installed.

There is a second half to the same problem: `InstallPath` must be a *Windows*
path. The games concatenate rather than join, so a POSIX value produces
`/Users/me/Games/BFME2\lotrbfme2ep1.exe`, which resolves to nothing.

## How it works

`BfmeGameRegistryProjection.project(state, through: bridge)`:

1. `winepath -w` translates the launcher's POSIX install path into the Windows
   path the game will see.
2. A `.reg` document is built and imported with `regedit /S`, followed by
   `wineserver -w` so the write is flushed to `system.reg`.

`BfmeLaunchManager.launchGame` calls this immediately before spawning the game.
The step is non-fatal: a prefix may already hold correct values, so a failure is
reported and the launch continues rather than being blocked.

### Three decisions worth knowing

**Writes go through `regedit`, not to `system.reg` directly.** A running
`wineserver` holds the registry in memory and rewrites those files on its own
schedule, so an external edit can be silently discarded.

**Every key is written twice, under `SOFTWARE\` and `SOFTWARE\WOW6432Node\`.**
The games are 32-bit. In a 64-bit prefix, WOW64 redirects a 32-bit process asking
for `SOFTWARE\X` to `SOFTWARE\WOW6432Node\X`, so only the redirected copy is
visible to the game; in a 32-bit prefix there is no redirector and no
`WOW6432Node` at all. Writing both is correct for either without having to detect
the prefix architecture. This was verified against Wine 11.17 rather than assumed
— see `WineIntegrationTests`.

**Reads use `regedit /E`, not `reg query`.** `reg.exe` writes its output in the
console's OEM codepage, so a path containing non-ASCII characters comes back as
mojibake and any comparison against what was written fails. A macOS account named
`José` is enough to trigger it. `regedit /E` emits UTF-16LE, which round trips
exactly. This was found by an integration test, not by inspection.

## Tests

```bash
swift test --filter BfmeWineBridgeTests          # hermetic, no Wine needed
```

The integration tests build a real throwaway prefix and are skipped unless a Wine
binary is supplied:

```bash
BFME_TEST_WINE_BIN=/path/to/bin/wine swift test --filter WineIntegrationTests
```

They assert the things unit tests structurally cannot: that a projected install
is visible through the 32-bit view the game actually uses, that dwords and the
`ergc` serial survive, that `%APPDATA%` resolves inside the prefix, that a
non-ASCII path round trips, and that an absent game reads back as nil.

## Still unresolved

- `Options.ini` is written to the host's `~/Library/Application Support`, not to
  the prefix's `%APPDATA%`. `WinePrefixBridge.applicationDataDirectory()` returns
  the correct location and is tested, but `BfmeRegistryManager.ensureDefaults`
  does not use it yet, so in-game graphics settings do not persist.
- `BfmeRegistryManager`'s `RegistryStore` remains the launcher's own cache. That
  is a reasonable design — reads stay fast and do not spawn Wine — but nothing
  currently reconciles the two if a user edits the prefix registry by hand.
- `ensureCompatibilitySettings` is a no-op, which is correct: it wrote
  `AppCompatFlags\Layers`, and Wine has no shim engine for those to drive.
