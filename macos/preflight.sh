#!/usr/bin/env bash
#
# preflight.sh - check whether this Mac can host the BFME All in One Launcher.
#
# The launcher is a Windows WPF application and the games it manages are 2004-2006 era
# 32-bit Direct3D 9 Windows games, so "running on macOS" means running inside a Windows
# guest. This script reports what the current Mac can provide and which hypervisor to use.
#
# Exits 0 if a usable path exists, 1 if the host cannot support any path.
#
# Written for the bash 3.2 that ships with macOS, so no bash 4+ syntax.

set -uo pipefail

MIN_MACOS_MAJOR=26
RECOMMENDED_DISK_GB=80
RECOMMENDED_RAM_GB=16

pass_count=0
warn_count=0
fail_count=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'
else
    C_RESET=''; C_BOLD=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''
fi

ok()   { printf '  %s[ ok ]%s   %s\n' "$C_GREEN" "$C_RESET" "$1"; pass_count=$((pass_count + 1)); }
warn() { printf '  %s[warn]%s   %s\n' "$C_YELLOW" "$C_RESET" "$1"; warn_count=$((warn_count + 1)); }
fail() { printf '  %s[fail]%s   %s\n' "$C_RED" "$C_RESET" "$1"; fail_count=$((fail_count + 1)); }
note() { printf '           %s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
head1() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }

# ---------------------------------------------------------------- host platform

head1 'Host platform'

if [ "$(uname -s)" != "Darwin" ]; then
    fail "Not macOS (uname reports '$(uname -s)'). This script is for macOS hosts."
    note "To build the launcher on a non-Mac, use macos/build-launcher.sh, which is portable."
    exit 1
fi

macos_version="$(sw_vers -productVersion 2>/dev/null || echo '0')"
macos_major="${macos_version%%.*}"

if [ "$macos_major" -ge "$MIN_MACOS_MAJOR" ] 2>/dev/null; then
    ok "macOS $macos_version (Tahoe 26 or newer)"
else
    fail "macOS $macos_version is older than the required $MIN_MACOS_MAJOR (Tahoe)"
    note "Update via System Settings > General > Software Update."
fi

host_arch="$(uname -m)"
case "$host_arch" in
    arm64)
        ok "Apple silicon ($(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'arm64'))"
        note "Windows guests will be Windows 11 on ARM. It emulates the x86/x64 code the"
        note "games need (WoW64 for 32-bit, Prism for 64-bit)."
        GUEST_RID='win-arm64'
        ;;
    x86_64)
        ok "Intel Mac ($host_arch)"
        note "Windows guests will be x64, which runs the games natively without emulation."
        note "Note macOS 26 Tahoe is the last release supporting Intel Macs."
        GUEST_RID='win-x64'
        ;;
    *)
        fail "Unrecognised architecture '$host_arch'"
        GUEST_RID='win-x64'
        ;;
esac

# ------------------------------------------------------------------- capacity

head1 'Capacity'

# df -k is portable; POSIX output puts available blocks in field 4.
avail_kb="$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${avail_kb:-}" ]; then
    avail_gb=$((avail_kb / 1024 / 1024))
    if [ "$avail_gb" -ge "$RECOMMENDED_DISK_GB" ]; then
        ok "${avail_gb} GB free on / (need about ${RECOMMENDED_DISK_GB} GB)"
    else
        warn "${avail_gb} GB free on /, about ${RECOMMENDED_DISK_GB} GB recommended"
        note "A Windows 11 guest needs ~64 GB, plus the ISO and each BFME install."
    fi
else
    warn "Could not determine free disk space"
fi

ram_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
ram_gb=$((ram_bytes / 1024 / 1024 / 1024))
if [ "$ram_gb" -ge "$RECOMMENDED_RAM_GB" ]; then
    ok "${ram_gb} GB RAM (can give the guest 8 GB comfortably)"
elif [ "$ram_gb" -ge 8 ]; then
    warn "${ram_gb} GB RAM - workable, give the guest 4-6 GB and close other apps"
else
    fail "${ram_gb} GB RAM is not enough to run a Windows 11 guest"
fi

cpu_count="$(sysctl -n hw.ncpu 2>/dev/null || echo 0)"
if [ "$cpu_count" -ge 8 ]; then
    ok "${cpu_count} CPU cores (assign 4 to the guest)"
elif [ "$cpu_count" -ge 4 ]; then
    warn "${cpu_count} CPU cores - assign 2 to the guest"
else
    warn "Only ${cpu_count} CPU cores detected"
fi

# ---------------------------------------------------------------- hypervisors

head1 'Virtualization software'

found_hypervisor=0
recommended=''

if [ -d '/Applications/Parallels Desktop.app' ]; then
    found_hypervisor=1
    recommended="${recommended:-parallels}"
    ok 'Parallels Desktop installed'
    note 'Best 3D support: DirectX 11 and OpenGL 4.3 for Windows on ARM guests, and it is'
    note 'a Microsoft-authorized way to license Windows 11 ARM. Paid, subscription.'
    if command -v prlctl >/dev/null 2>&1; then
        note "prlctl available: $(prlctl --version 2>&1 | head -1)"
    fi
else
    note 'Parallels Desktop not installed  (best 3D support, paid)'
fi

if [ -d '/Applications/VMware Fusion.app' ]; then
    found_hypervisor=1
    recommended="${recommended:-fusion}"
    ok 'VMware Fusion installed'
    note 'Free for personal use, supports Windows 11 ARM guests. 3D support is weaker'
    note 'than Parallels, so expect to need the software renderer for the games.'
else
    note 'VMware Fusion not installed     (free for personal use)'
fi

if [ -d '/Applications/UTM.app' ]; then
    found_hypervisor=1
    recommended="${recommended:-utm}"
    ok 'UTM installed'
    utm_plist='/Applications/UTM.app/Contents/Info.plist'
    if [ -f "$utm_plist" ]; then
        utm_version="$(defaults read "$utm_plist" CFBundleShortVersionString 2>/dev/null || echo 'unknown')"
        note "Version $utm_version"
        case "$utm_version" in
            [0-4].*)
                warn 'UTM 4.x has no 3D acceleration for Windows guests'
                note 'The launcher UI will work, but the games will not get a hardware'
                note 'Direct3D device. Upgrade to UTM 5.x or use Parallels for the games.'
                ;;
        esac
    fi
    note 'Free and open source. 3D for Windows guests is new and still experimental.'
else
    note 'UTM not installed               (free, open source)'
fi

if [ -d '/Applications/CrossOver.app' ]; then
    ok 'CrossOver installed (Wine, no VM)'
    note 'Alternative to a VM with no Windows license needed, but see the caveats in'
    note 'macos/README.md - the launcher needs software rendering and the Arena tab'
    note 'will not work. On Apple silicon this path also depends on x86 translation,'
    note 'which Apple is removing in macOS 28.'
else
    note 'CrossOver not installed         (Wine, no Windows license, more caveats)'
fi

if [ "$found_hypervisor" -eq 0 ]; then
    warn 'No hypervisor found'
    note 'Install one, for example:  brew install --cask utm'
    note '                      or:  brew install --cask vmware-fusion'
fi

# -------------------------------------------------------------- build toolchain

head1 'Build toolchain (only needed to build the launcher yourself)'

if command -v dotnet >/dev/null 2>&1; then
    sdk_list="$(dotnet --list-sdks 2>/dev/null | awk '{print $1}')"
    if printf '%s\n' "$sdk_list" | grep -q '^8\.'; then
        ok ".NET SDK 8 present ($(printf '%s' "$sdk_list" | grep '^8\.' | tail -1))"
    elif [ -n "$sdk_list" ]; then
        ok ".NET SDK present ($(printf '%s\n' "$sdk_list" | tail -1))"
        note 'The launcher targets net8.0-windows. A newer SDK can still build it.'
    else
        warn 'dotnet found but no SDKs installed'
    fi
else
    warn '.NET SDK not installed'
    note 'Install with:  brew install --cask dotnet-sdk'
    note 'Only needed to build the launcher. You can also just download the official'
    note 'build inside the Windows guest from https://bfmeladder.com/download'
fi

# --------------------------------------------------------------------- summary

head1 'Summary'

printf '  %d passed, %d warnings, %d failures\n' "$pass_count" "$warn_count" "$fail_count"
printf '  Guest runtime identifier for this host: %s%s%s\n' "$C_BOLD" "$GUEST_RID" "$C_RESET"

if [ "$fail_count" -gt 0 ]; then
    printf '\n  %sThis Mac cannot host the launcher as configured.%s See the failures above.\n\n' "$C_RED" "$C_RESET"
    exit 1
fi

cat <<EOF

  Next steps:
    1. Install a hypervisor and a Windows 11 guest  (see macos/README.md)
    2. Build the guest bundle on this Mac:
         ./macos/build-launcher.sh --rid $GUEST_RID
    3. Copy the bundle into the guest and run, in an elevated PowerShell:
         .\\provision-guest.ps1

EOF

exit 0
