<#
.SYNOPSIS
    Installs the All in One Launcher inside a Windows virtual machine running on a Mac.

.DESCRIPTION
    Run this inside the Windows guest, in an elevated PowerShell, from the folder produced
    by macos/build-launcher.sh.

    It does four things:

      1. Reports whether this guest can actually run the BFME games, which comes down to
         whether the virtual GPU exposes a real Direct3D device. This is the single most
         common reason the games fail in a VM, so it is checked first and loudly.
      2. Copies the launcher into %APPDATA%\BFME All In One Launcher. A Release build
         refuses to start from anywhere else, so the location is not optional.
      3. Sets the compatibility switches the launcher reads, so it does not overwrite
         itself with the official x64 build and, optionally, does not run the legacy
         32-bit DXSETUP installer.
      4. Creates a desktop shortcut that requests Administrator, which the launcher needs
         in order to write the HKLM keys the games read.

.PARAMETER SourcePath
    Folder holding the published launcher. Defaults to .\AllInOneLauncher next to this script.

.PARAMETER RenderMode
    WPF render mode for the launcher UI.
      auto      (default) hardware, except under Wine where it falls back to software
      software  force software rendering - use if the launcher window is black or crashes
      hardware  force hardware rendering

.PARAMETER SkipDirectXRuntime
    Stop the launcher running the bundled DirectX 9 redistributable. DXSETUP.exe is a legacy
    32-bit x86 installer, so on a Windows-on-ARM guest it runs under emulation. Use this if
    you have already installed DirectX 9 in the guest, or if DXSETUP hangs.

.PARAMETER EnableSelfUpdate
    Allow the launcher to update itself from bfmeladder.com. Off by default, because the
    official build is win-x64 and would replace an arm64 build you deliberately made.

.PARAMETER CheckOnly
    Only run the environment report. Changes nothing.

.EXAMPLE
    .\provision-guest.ps1
    Install with defaults.

.EXAMPLE
    .\provision-guest.ps1 -CheckOnly
    Just report on the guest's suitability.

.EXAMPLE
    .\provision-guest.ps1 -RenderMode software -SkipDirectXRuntime
    Install for a guest with no working 3D acceleration.
#>

[CmdletBinding()]
param(
    [string] $SourcePath,

    [ValidateSet('auto', 'software', 'hardware')]
    [string] $RenderMode = 'auto',

    [switch] $SkipDirectXRuntime,

    [switch] $EnableSelfUpdate,

    [switch] $CheckOnly
)

$ErrorActionPreference = 'Stop'

# The launcher's LauncherUpdateManager.LauncherAppDirectory, and the Release-build check in
# App.xaml.cs, both resolve to exactly this path. It cannot be changed here.
$InstallDir   = Join-Path $env:APPDATA 'BFME All In One Launcher'
$LauncherExe  = 'AllInOneLauncher.exe'
$MarkerFile   = 'no-self-update'

$script:Problems = @()
$script:Warnings = @()

function Write-Head { param([string] $Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor DarkGray
}
function Write-Ok   { param([string] $Text) Write-Host '  [ ok ] ' -ForegroundColor Green  -NoNewline; Write-Host $Text }
function Write-Warn { param([string] $Text) Write-Host '  [warn] ' -ForegroundColor Yellow -NoNewline; Write-Host $Text; $script:Warnings += $Text }
function Write-Bad  { param([string] $Text) Write-Host '  [fail] ' -ForegroundColor Red    -NoNewline; Write-Host $Text; $script:Problems += $Text }
function Write-Note { param([string] $Text) Write-Host "         $Text" -ForegroundColor DarkGray }

function Test-Admin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Reads the COFF machine field so we can tell an arm64 bundle from an x64 one.
function Get-PeArchitecture {
    param([Parameter(Mandatory = $true)][string] $Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] 1024
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -lt 64) { return 'unknown' }

        $peOffset = [System.BitConverter]::ToInt32($buffer, 0x3c)
        if ($peOffset -le 0 -or ($peOffset + 6) -ge $read) { return 'unknown' }

        $machine = [System.BitConverter]::ToUInt16($buffer, $peOffset + 4)
        switch ($machine) {
            0x8664  { return 'x64' }
            0xaa64  { return 'arm64' }
            0x14c   { return 'x86' }
            default { return ('unknown(0x{0:x4})' -f $machine) }
        }
    }
    finally {
        $stream.Dispose()
    }
}

Write-Host ''
Write-Host ' All in One Launcher - Windows guest provisioning ' -ForegroundColor White -BackgroundColor DarkBlue

# ---------------------------------------------------------------------- checks

Write-Head 'Guest environment'

if (Test-Admin) {
    Write-Ok 'Running elevated'
} else {
    Write-Bad 'Not running as Administrator'
    Write-Note 'The launcher writes HKLM registry keys and needs elevation. Re-open'
    Write-Note 'PowerShell with "Run as Administrator" and run this script again.'
}

$os = Get-CimInstance Win32_OperatingSystem
Write-Ok ("Windows: {0} (build {1})" -f $os.Caption.Trim(), $os.BuildNumber)

$osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
Write-Ok "Guest architecture: $osArch"

if ($osArch -eq 'arm64') {
    Write-Note 'Windows on ARM. It emulates the x86 and x64 code the BFME games need:'
    Write-Note 'WoW64 handles the 32-bit game executables, and Prism (Windows 11 24H2'
    Write-Note 'and newer) handles 64-bit ones. Expect a CPU cost but it does work.'
    if ([int] $os.BuildNumber -lt 26100) {
        Write-Warn 'Build is older than 26100 (24H2), so it predates the Prism emulator'
        Write-Note 'Update Windows for noticeably better emulated performance.'
    }
}

# The decisive question for whether the games will run at all.
Write-Head 'Graphics (this decides whether the games will run)'

$gpus = @(Get-CimInstance Win32_VideoController)
if ($gpus.Count -eq 0) {
    Write-Warn 'No display adapter reported'
} else {
    foreach ($gpu in $gpus) {
        $name = $gpu.Name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = '(unnamed adapter)' }

        if ($name -match 'Basic Display|Basic Render') {
            Write-Bad "Adapter: $name"
            Write-Note 'This is the fallback software adapter: there is no Direct3D'
            Write-Note 'acceleration in this guest. The launcher UI will still work, but'
            Write-Note 'the BFME games will run very slowly or refuse to start.'
            Write-Note 'Fix: install the guest tools for your hypervisor (Parallels Tools,'
            Write-Note 'VMware Tools, or SPICE tools for UTM). If your hypervisor simply'
            Write-Note 'has no 3D driver for Windows guests, the games will not be playable'
            Write-Note 'and you need a different hypervisor. See macos/README.md.'
        } else {
            Write-Ok "Adapter: $name"
            if ($gpu.DriverVersion) { Write-Note "Driver $($gpu.DriverVersion)" }
        }
    }
}

# d3dx9_43 is what the games actually link against, shipped by the DX9 redist.
$sysD3dx9  = Test-Path (Join-Path $env:WINDIR 'System32\d3dx9_43.dll')
$wowD3dx9  = Test-Path (Join-Path $env:WINDIR 'SysWOW64\d3dx9_43.dll')
if ($sysD3dx9 -and $wowD3dx9) {
    Write-Ok 'DirectX 9 runtime (d3dx9_43) already present'
} else {
    Write-Note 'DirectX 9 runtime (d3dx9_43) not fully present yet - the launcher installs'
    Write-Note 'it on first mod or patch sync, unless -SkipDirectXRuntime is used.'
}

# ------------------------------------------------------------------- the bundle

Write-Head 'Launcher bundle'

if (-not $SourcePath) {
    $SourcePath = Join-Path $PSScriptRoot 'AllInOneLauncher'
}

$bundleExe = Join-Path $SourcePath $LauncherExe

if (Test-Path $bundleExe) {
    Write-Ok "Found $SourcePath"

    $bundleArch = Get-PeArchitecture -Path $bundleExe
    if ($bundleArch -eq $osArch) {
        Write-Ok "Bundle is $bundleArch, matching this guest - it will run natively"
    } elseif ($osArch -eq 'arm64' -and $bundleArch -eq 'x64') {
        Write-Warn "Bundle is x64 on an arm64 guest - it will run under emulation"
        Write-Note 'It will work, just slower to start. For a native build, rebuild on'
        Write-Note 'the Mac with:  ./macos/build-launcher.sh --rid win-arm64'
    } elseif ($osArch -eq 'x64' -and $bundleArch -eq 'arm64') {
        Write-Bad "Bundle is arm64 but this guest is x64 - it cannot run here"
        Write-Note 'Rebuild on the Mac with:  ./macos/build-launcher.sh --rid win-x64'
    } else {
        Write-Warn "Bundle architecture is $bundleArch, guest is $osArch"
    }

    if (Test-Path (Join-Path $SourcePath 'coreclr.dll')) {
        Write-Ok 'Self-contained bundle: no .NET runtime needed in the guest'
    } else {
        Write-Note 'Framework-dependent bundle: the guest needs the .NET 8 Desktop Runtime.'
        Write-Note 'Get it with:  winget install Microsoft.DotNet.DesktopRuntime.8'
    }
} else {
    Write-Bad "No launcher found at $SourcePath"
    Write-Note "Expected $LauncherExe inside that folder. Build it on the Mac with"
    Write-Note './macos/build-launcher.sh and copy the whole output folder into the guest.'
}

if ($CheckOnly) {
    Write-Head 'Summary (check only, nothing was changed)'
    Write-Host ("  {0} problem(s), {1} warning(s)" -f $script:Problems.Count, $script:Warnings.Count)
    Write-Host ''
    if ($script:Problems.Count -gt 0) { exit 1 }
    exit 0
}

if ($script:Problems.Count -gt 0) {
    Write-Head 'Stopping'
    Write-Host '  Fix the [fail] items above, then run this script again.' -ForegroundColor Red
    Write-Host '  Run with -CheckOnly to re-check without installing.' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

# ------------------------------------------------------------------- installing

Write-Head 'Installing'

# The launcher may be running from a previous attempt and would lock its own files.
$running = @(Get-Process -Name 'AllInOneLauncher' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    Write-Note 'Stopping a running launcher instance first'
    $running | Stop-Process -Force
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
Write-Ok "Install directory: $InstallDir"

Copy-Item -Path (Join-Path $SourcePath '*') -Destination $InstallDir -Recurse -Force
Write-Ok ("Copied {0} file(s)" -f @(Get-ChildItem -Path $InstallDir -Recurse -File).Count)

if ($EnableSelfUpdate) {
    Remove-Item -Path (Join-Path $InstallDir $MarkerFile) -Force -ErrorAction SilentlyContinue
    Write-Warn 'Self-update enabled - the official win-x64 build may replace this one'
} else {
    Set-Content -Path (Join-Path $InstallDir $MarkerFile) `
                -Value 'Provisioned by macos/provision-guest.ps1. Delete to re-enable self-updates.' `
                -Encoding ASCII
    Write-Ok 'Self-update disabled (delete the no-self-update file to re-enable)'
}

# Machine scope so the elevated launcher sees these regardless of how it is started.
if ($RenderMode -eq 'auto') {
    [Environment]::SetEnvironmentVariable('BFME_RENDER_MODE', $null, 'Machine')
    Write-Ok 'Render mode: auto'
} else {
    [Environment]::SetEnvironmentVariable('BFME_RENDER_MODE', $RenderMode, 'Machine')
    Write-Ok "Render mode: $RenderMode (BFME_RENDER_MODE set machine-wide)"
}

if ($SkipDirectXRuntime) {
    [Environment]::SetEnvironmentVariable('BFME_SKIP_DX_RUNTIME', '1', 'Machine')
    Write-Ok 'DirectX 9 redistributable: will be skipped (BFME_SKIP_DX_RUNTIME=1)'
} else {
    [Environment]::SetEnvironmentVariable('BFME_SKIP_DX_RUNTIME', $null, 'Machine')
    Write-Ok 'DirectX 9 redistributable: will be installed by the launcher when needed'
}

# The launcher makes its own shortcuts on first run, but it has to start once to do that,
# and it must start elevated. This shortcut has the elevation flag set from the outset.
try {
    $desktop      = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'All in One Launcher.lnk'
    $shell        = New-Object -ComObject WScript.Shell
    $shortcut     = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath       = Join-Path $InstallDir $LauncherExe
    $shortcut.WorkingDirectory = $InstallDir
    $shortcut.Description      = 'All in One Launcher'
    $shortcut.Save()

    # Byte 21 bit 0x20 of a .lnk is the "run as administrator" flag, which the
    # WScript.Shell COM object cannot set on its own.
    $bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
    $bytes[21] = $bytes[21] -bor 0x20
    [System.IO.File]::WriteAllBytes($shortcutPath, $bytes)

    Write-Ok 'Desktop shortcut created (set to run as Administrator)'
} catch {
    Write-Warn "Could not create the desktop shortcut: $($_.Exception.Message)"
    Write-Note "Start the launcher directly from $InstallDir instead."
}

# --------------------------------------------------------------------- summary

Write-Head 'Done'

Write-Host "  Launcher installed to $InstallDir"
Write-Host ''
Write-Host '  Start it from the desktop shortcut, and accept the UAC prompt.'
Write-Host ''
Write-Host '  Then, inside the launcher:' -ForegroundColor White
Write-Host '    - Install or point it at BFME 1, BFME 2 or ROTWK. It writes the HKLM'
Write-Host '      registry keys the games use to locate themselves.'
Write-Host '    - Patches and mods come from the Workshop tab.'
Write-Host ''
Write-Host '  Known limits in a VM:' -ForegroundColor White
Write-Host '    - The Online/Arena tab embeds a separate process window into the launcher.'
Write-Host '      That works on real Windows but is unreliable in a guest.'
Write-Host '    - If the launcher window is black, re-run with:  -RenderMode software'
Write-Host '    - If a mod sync hangs on "Installing DX9 runtime", re-run with:'
Write-Host '      -SkipDirectXRuntime'
Write-Host ''

if ($script:Warnings.Count -gt 0) {
    Write-Host ("  Finished with {0} warning(s) - see above." -f $script:Warnings.Count) -ForegroundColor Yellow
    Write-Host ''
}

exit 0
