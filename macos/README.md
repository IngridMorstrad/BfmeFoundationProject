# Running the All in One Launcher on macOS (Tahoe 26 or newer)

The launcher is a .NET 8 **WPF** application, and the games it manages are 2004-2006 era
**32-bit Direct3D 9 Windows** games. There is no macOS-native port of WPF, and more
importantly there is nothing to port *to*: the launcher's job is to write the Windows
registry keys that BFME 1, BFME 2 and ROTWK read to find themselves, install the DirectX 9
runtime, and launch Windows `.exe` files.

So "running on macOS" means **running Windows on the Mac, and running the launcher inside
it**. That is not a workaround, it is the only arrangement in which the launcher is useful,
because the games have to live in the same place as the launcher managing them.

This directory automates the parts that can be automated:

| File | Runs on | Purpose |
| --- | --- | --- |
| `preflight.sh` | macOS | Checks this Mac can host a Windows guest, and which hypervisor to use |
| `build-launcher.sh` | macOS or Linux | Cross-builds a Windows launcher bundle, `win-arm64` or `win-x64` |
| `provision-guest.ps1` | Windows guest | Installs the bundle, reports whether the guest can run the games |

---

## Quick start

```bash
# 1. On the Mac: can this machine do it, and what should the guest be?
./macos/preflight.sh

# 2. Install a hypervisor and a Windows 11 guest  (see "Choosing a hypervisor" below)

# 3. On the Mac: build a launcher for the guest.
#    Defaults to win-arm64 on Apple silicon, win-x64 on Intel.
./macos/build-launcher.sh

# 4. Copy dist/macos/<rid>/ into the guest, then in an ELEVATED PowerShell there:
#      Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#      .\provision-guest.ps1
```

`provision-guest.ps1 -CheckOnly` reports on the guest without changing anything, which is
the fastest way to find out whether a given VM setup is going to work.

---

## Choosing a hypervisor

On Apple silicon a Mac can only virtualize **ARM** guests, so the guest is Windows 11 on
ARM. That is fine for the games: Windows on ARM emulates x86 and x64 code, with the older
WoW64 layer handling 32-bit executables and the newer Prism emulator handling 64-bit ones
from Windows 11 24H2 onward
([Microsoft](https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation)).
The BFME games are 32-bit, so they go through the emulation path that has existed the
longest.

The thing that actually decides whether the games are playable is **whether the virtual GPU
exposes a real Direct3D device**. This is where the hypervisors differ sharply:

| | 3D for Windows guests | Cost | Notes |
| --- | --- | --- | --- |
| **Parallels Desktop** | DirectX 11, OpenGL 4.3 | Paid | The most reliable choice for the games. Also a Microsoft-authorized route to a licensed Windows 11 ARM guest ([Parallels](https://www.parallels.com/products/desktop/microsoft-authorized-solution-windows-11-arm/), [OpenGL support](https://kb.parallels.com/en/115487)) |
| **VMware Fusion** | Limited | Free for personal use | Runs Windows 11 ARM guests; weaker 3D, so expect to need software rendering |
| **UTM** | New and experimental | Free, open source | UTM historically shipped **no** 3D acceleration for Windows guests ([UTM docs / community](https://apple.stackexchange.com/questions/455562/running-gl-applications-through-utm-glx-failed-to-create-context-glxbadfbconf)). UTM 5.x added a Direct3D 12 driver, but the project describes it as experimental with limited game compatibility ([release notes](https://github.com/utmapp/UTM/releases)) |

**Recommendation.** If you want to *play the games*, use Parallels Desktop. If you mainly
want the launcher, the Workshop and mod management and can tolerate poor in-game
performance, UTM is free and adequate — `provision-guest.ps1` will tell you which situation
you are in by inspecting the guest's display adapter.

You need a valid Windows 11 licence either way. Parallels handles acquiring and licensing
the guest for you; with UTM or Fusion you supply your own Windows 11 ARM64 ISO (the UTM
authors' [CrystalFetch](https://github.com/TuringSoftware/CrystalFetch) app builds one) and
your own licence key.

---

## Building the launcher on the Mac

WPF normally refuses to build off Windows. The .NET SDK will do it anyway when
`EnableWindowsTargeting` is set, which is what `build-launcher.sh` passes. The output is an
ordinary Windows binary that happens to have been produced on macOS.

```bash
./macos/build-launcher.sh                      # auto-detects the right target
./macos/build-launcher.sh --rid win-x64        # for an Intel Mac or an x64 guest
./macos/build-launcher.sh --configuration Debug
./macos/build-launcher.sh --help
```

Requires the .NET SDK (`brew install --cask dotnet-sdk`).

The script builds **self-contained** by default, so the guest needs no .NET runtime
installed, and it verifies the produced `.exe`'s PE header actually matches the requested
architecture before declaring success.

**On Apple silicon, prefer `win-arm64`.** The launcher then runs *natively* in the guest and
only the games go through emulation. A `win-x64` launcher would itself be emulated, for no
benefit.

Because a locally built launcher is not the official build, the bundle includes a
`no-self-update` marker file. Without it the launcher would notice its own hash is unknown
to the update server and replace itself with the official `win-x64` download on first run,
undoing an `arm64` build.

### Building a Debug bundle

`--configuration Debug` compiles out two things that get in the way while experimenting: the
self-updater, and the check that refuses to run the launcher from anywhere other than
`%APPDATA%\BFME All In One Launcher`.

---

## Installing in the guest

Copy the bundle folder in (a shared folder or drag and drop), then from an **elevated**
PowerShell in that folder:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\provision-guest.ps1
```

Elevation is not optional: the launcher writes `HKEY_LOCAL_MACHINE` keys, which is how the
games locate their own install directories.

Useful variations:

```powershell
.\provision-guest.ps1 -CheckOnly                          # report only, change nothing
.\provision-guest.ps1 -RenderMode software                # launcher window is black/crashing
.\provision-guest.ps1 -SkipDirectXRuntime                 # DXSETUP hangs under emulation
.\provision-guest.ps1 -RenderMode software -SkipDirectXRuntime
```

The script installs to `%APPDATA%\BFME All In One Launcher` (required — a Release build
refuses to start elsewhere) and creates a desktop shortcut pre-flagged to run as
Administrator.

---

## Compatibility switches

These are read by the launcher at runtime. All of them default to stock Windows behaviour,
so none of this costs anything on a normal PC.

| Variable | Values | Effect |
| --- | --- | --- |
| `BFME_RENDER_MODE` | `auto` (default), `software`, `hardware` | WPF render mode. `auto` uses hardware rendering, except under Wine where WPF's Direct3D 9 usage is not reliable |
| `BFME_DISABLE_SELF_UPDATE` | `1`/`true` | Stops the launcher replacing itself with the official build. A `no-self-update` file in the install directory does the same |
| `BFME_SKIP_DX_RUNTIME` | `1`/`true` | Skips the bundled DirectX 9 redistributable. `DXSETUP.exe` is a legacy 32-bit installer, so it runs under emulation on ARM guests |

---

## What works, and what does not

Working, in a VM with a functioning 3D driver:

- The launcher UI, Workshop browsing, patch and mod installation and switching
- Installing and launching BFME 1, BFME 2 and ROTWK
- Registry management, map and language handling, DirectX 9 provisioning

Expect problems with:

- **The Online / Arena tab.** It launches a separate `BfmeFoundationProject_OnlineArena.exe`
  and reparents that process's window into the launcher with the Win32 `SetParent` API.
  Cross-process window embedding is reliable on real Windows and frequently is not in a
  guest or under Wine. Expect it to render detached, black, or mispositioned. That binary
  is also not part of this repository.
- **Game performance.** Emulated 32-bit D3D9 on a paravirtualized GPU is a lot of layers.
  Lower the in-game resolution first.
- **The resolution dropdown in settings.** It enumerates display modes with
  `EnumDisplaySettings` and then discards the three smallest. A guest that reports few modes
  can leave the list nearly empty.
- **Hard links.** Workshop content is hard-linked from a cache into the game directory, and
  the failure is silent. Keep the cache (`%APPDATA%\BFME Workshop`) and the games on the same
  virtual disk.

---

## The Wine / CrossOver alternative

[CrossOver](https://www.codeweavers.com/crossover) runs Windows applications without a
Windows licence or a full VM. The launcher does start under it — the code detects Wine and
switches WPF to software rendering automatically, because WPF's Direct3D 9 usage crashes
otherwise.

It is nonetheless the harder path, and not the recommended one:

- The Arena tab will not work (see above).
- `DXSETUP.exe` is unreliable under Wine. Pre-install DirectX 9 with `winetricks d3dx9` and
  set `BFME_SKIP_DX_RUNTIME=1` so the launcher does not try to reinstall it. The launcher no
  longer deletes the existing `d3dx9_43.dll` before it has confirmed a replacement
  installer, but avoiding the whole path is still safer.
- Install the launcher into the prefix's `%APPDATA%\BFME All In One Launcher`, or a Release
  build will refuse to start.
- On Apple silicon this path depends on x86 translation. Apple is phasing out Rosetta 2
  from macOS 28 ([Apple](https://developer.apple.com/news/?id=w5ngl9k2)), and CodeWeavers is
  moving CrossOver to an ARM64-native build with its own FEX emulator in response. Treat the
  Wine route as less stable over time than a VM.

A VM costs more disk and a Windows licence, and in exchange behaves like the environment the
launcher and the games were actually written for.

---

## Troubleshooting

**Launcher window is black, or it exits immediately.**
Re-run `provision-guest.ps1 -RenderMode software`. The guest's GPU driver does not give WPF a
usable Direct3D 9 device.

**"You already have the All In One Launcher installed".**
A Release build only runs from `%APPDATA%\BFME All In One Launcher`. Start it from the desktop
shortcut, or re-run `provision-guest.ps1`.

**A mod or patch sync hangs on "Installing DX9 runtime".**
`DXSETUP.exe` is stuck under emulation. Re-run with `-SkipDirectXRuntime`, and install
DirectX 9 in the guest yourself if the games then complain about `d3dx9_43.dll`.

**The launcher replaced itself and is now the official x64 build.**
The `no-self-update` marker was lost. Re-run `provision-guest.ps1`.

**Games launch but run at single-digit frame rates.**
Check `provision-guest.ps1 -CheckOnly`. A "Microsoft Basic Display Adapter" means there is no
3D acceleration at all — install your hypervisor's guest tools, or move to one with a real
Direct3D driver for Windows guests.

**`dotnet publish` fails with NETSDK1100 or complains about Windows targeting.**
Use `build-launcher.sh`, which passes `-p:EnableWindowsTargeting=true`.
