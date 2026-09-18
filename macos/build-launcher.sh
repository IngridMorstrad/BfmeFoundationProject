#!/usr/bin/env bash
#
# build-launcher.sh - build a Windows-guest-ready bundle of the All in One Launcher
#                     from a macOS (or Linux) host.
#
# WPF cannot be built on a non-Windows host by default, but the .NET SDK will do it when
# EnableWindowsTargeting is set. That is all that is needed: the output is a normal Windows
# binary, it just gets produced on the Mac and then run inside the Windows guest.
#
# The bundle is self-contained by default so the guest needs no .NET runtime installed, and
# it carries a 'no-self-update' marker so the launcher does not immediately replace itself
# with the official win-x64 download (which would undo the point of building for arm64).
#
# Written for the bash 3.2 that ships with macOS, so no bash 4+ syntax.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/src/BfmeFoundationProject_AllInOneLauncher/BfmeFoundationProject_AllInOneLauncher.csproj"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_DIM=$'\033[2m'
else
    C_RESET=''; C_BOLD=''; C_GREEN=''; C_RED=''; C_DIM=''
fi

info() { printf '%s==>%s %s\n' "$C_BOLD" "$C_RESET" "$1"; }
good() { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
die()  { printf '%serror:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; exit 1; }

# ------------------------------------------------------------------- arguments

default_rid() {
    if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
        echo 'win-arm64'
    elif [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
        echo 'win-arm64'
    else
        echo 'win-x64'
    fi
}

RID="$(default_rid)"
CONFIGURATION='Release'
OUTPUT_DIR=''
SELF_CONTAINED='true'
MAKE_ZIP='true'

usage() {
    cat <<EOF
${C_BOLD}build-launcher.sh${C_RESET} - build a Windows bundle of the All in One Launcher

Usage: $0 [options]

Options:
  --rid <rid>            Target runtime: win-arm64 or win-x64.
                         Default for this host: $(default_rid)
  --configuration <cfg>  Release (default) or Debug. Debug disables the self-updater
                         and the install-location check at compile time.
  --output <dir>         Output directory. Default: <repo>/dist/macos/<rid>
  --framework-dependent  Do not bundle the .NET runtime. The guest will then need the
                         .NET 8 Desktop Runtime installed.
  --no-zip               Leave the bundle as a directory, do not create a .zip.
  -h, --help             Show this help.

Which RID to pick:
  Apple silicon Mac -> the guest is Windows 11 on ARM   -> win-arm64
                       (the launcher then runs natively; only the games are emulated)
  Intel Mac         -> the guest is Windows x64         -> win-x64

Examples:
  $0                                 # sensible defaults for this Mac
  $0 --rid win-x64                   # for an Intel Mac or an x64 guest
  $0 --configuration Debug           # no self-update, no install-location check
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --rid)
            [ $# -ge 2 ] || die "--rid needs a value"
            RID="$2"; shift 2 ;;
        --configuration)
            [ $# -ge 2 ] || die "--configuration needs a value"
            CONFIGURATION="$2"; shift 2 ;;
        --output)
            [ $# -ge 2 ] || die "--output needs a value"
            OUTPUT_DIR="$2"; shift 2 ;;
        --framework-dependent)
            SELF_CONTAINED='false'; shift ;;
        --no-zip)
            MAKE_ZIP='false'; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            die "unknown option '$1'  (try --help)" ;;
    esac
done

case "$RID" in
    win-arm64|win-x64) ;;
    *) die "unsupported --rid '$RID'. Use win-arm64 or win-x64." ;;
esac

case "$CONFIGURATION" in
    Release|Debug) ;;
    *) die "unsupported --configuration '$CONFIGURATION'. Use Release or Debug." ;;
esac

[ -n "$OUTPUT_DIR" ] || OUTPUT_DIR="$REPO_ROOT/dist/macos/$RID"
PUBLISH_DIR="$OUTPUT_DIR/AllInOneLauncher"

# ------------------------------------------------------------------ toolchain

command -v dotnet >/dev/null 2>&1 || die ".NET SDK not found. Install it with: brew install --cask dotnet-sdk"
[ -f "$PROJECT" ] || die "launcher project not found at $PROJECT"

info "Building the All in One Launcher"
printf '    repo           %s\n' "$REPO_ROOT"
printf '    runtime        %s\n' "$RID"
printf '    configuration  %s\n' "$CONFIGURATION"
printf '    self-contained %s\n' "$SELF_CONTAINED"
printf '    output         %s\n' "$OUTPUT_DIR"
printf '    dotnet SDK     %s\n' "$(dotnet --version 2>/dev/null || echo unknown)"

rm -rf "$PUBLISH_DIR"
mkdir -p "$PUBLISH_DIR"

# EnableWindowsTargeting lets a non-Windows host build a net8.0-windows / WPF project.
info "Running dotnet publish (this pulls NuGet packages on first run)"
dotnet publish "$PROJECT" \
    --configuration "$CONFIGURATION" \
    --runtime "$RID" \
    --output "$PUBLISH_DIR" \
    -p:SelfContained="$SELF_CONTAINED" \
    -p:EnableWindowsTargeting=true \
    -p:PublishSingleFile=false \
    --nologo \
    --verbosity minimal

LAUNCHER_EXE="$PUBLISH_DIR/AllInOneLauncher.exe"
[ -f "$LAUNCHER_EXE" ] || die "publish finished but $LAUNCHER_EXE is missing"

# ------------------------------------------------------- verify the output arch

# Read the PE header machine field so a RID/arch mismatch is caught here rather than
# as an unhelpful error inside the guest.
verify_arch() {
    python3 - "$1" "$2" <<'PY'
import struct, sys
path, expected = sys.argv[1], sys.argv[2]
names = {0x8664: 'win-x64', 0xaa64: 'win-arm64', 0x14c: 'win-x86'}
with open(path, 'rb') as fh:
    head = fh.read(0x400)
pe = struct.unpack_from('<I', head, 0x3c)[0]
machine = struct.unpack_from('<H', head, pe + 4)[0]
actual = names.get(machine, 'unknown(0x%04x)' % machine)
print(actual)
sys.exit(0 if actual == expected else 1)
PY
}

if command -v python3 >/dev/null 2>&1; then
    if actual_arch="$(verify_arch "$LAUNCHER_EXE" "$RID")"; then
        good "AllInOneLauncher.exe is a $actual_arch binary"
    else
        die "built binary is $actual_arch but $RID was requested"
    fi
else
    printf '    %s(python3 not available, skipping architecture verification)%s\n' "$C_DIM" "$C_RESET"
fi

# --------------------------------------------------------------- bundle extras

# The launcher hashes its own exe and compares against the update server. A locally built
# exe never matches, so without this marker it would download the official win-x64 build
# over the top of this one on first launch.
printf 'Built locally by macos/build-launcher.sh for %s.\nRemove this file to re-enable launcher self-updates.\n' "$RID" \
    > "$PUBLISH_DIR/no-self-update"
good "wrote no-self-update marker"

if [ -f "$SCRIPT_DIR/provision-guest.ps1" ]; then
    cp "$SCRIPT_DIR/provision-guest.ps1" "$OUTPUT_DIR/provision-guest.ps1"
    good "copied provision-guest.ps1"
else
    printf '    %swarning: provision-guest.ps1 not found next to this script%s\n' "$C_DIM" "$C_RESET"
fi

cat > "$OUTPUT_DIR/README.txt" <<EOF
All in One Launcher - bundle for a Windows guest
================================================

  runtime          $RID
  configuration    $CONFIGURATION
  self-contained   $SELF_CONTAINED
  built            $(date -u '+%Y-%m-%d %H:%M:%S UTC')

Install inside the Windows virtual machine
------------------------------------------
1. Copy this whole folder into the guest (shared folder, or drag and drop).
2. Open PowerShell as Administrator in this folder.
3. Allow the script to run for this session, then run it:

     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
     .\provision-guest.ps1

The launcher must live in %APPDATA%\BFME All In One Launcher, because a Release build
refuses to run from anywhere else. provision-guest.ps1 puts it there for you.

The launcher needs Administrator rights: it writes the HKLM registry keys the BFME games
read to find their own install directories.
EOF
good "wrote README.txt"

# ------------------------------------------------------------------------- zip

if [ "$MAKE_ZIP" = 'true' ]; then
    ZIP_PATH="$OUTPUT_DIR/AllInOneLauncher-$RID.zip"
    rm -f "$ZIP_PATH"
    info "Creating $ZIP_PATH"
    if command -v ditto >/dev/null 2>&1; then
        # ditto is the macOS-native option and preserves the layout cleanly.
        ( cd "$OUTPUT_DIR" && ditto -c -k --sequesterRsrc "AllInOneLauncher" "$ZIP_PATH" )
    elif command -v zip >/dev/null 2>&1; then
        ( cd "$OUTPUT_DIR" && zip -q -r "$ZIP_PATH" "AllInOneLauncher" )
    elif command -v python3 >/dev/null 2>&1; then
        ( cd "$OUTPUT_DIR" && python3 -c "
import shutil, sys
shutil.make_archive(sys.argv[1][:-4], 'zip', '.', 'AllInOneLauncher')
" "$ZIP_PATH" )
    else
        printf '    %sno zip tool found, leaving the directory as-is%s\n' "$C_DIM" "$C_RESET"
        ZIP_PATH=''
    fi
    [ -z "$ZIP_PATH" ] || good "$(du -h "$ZIP_PATH" | cut -f1) $(basename "$ZIP_PATH")"
fi

# --------------------------------------------------------------------- summary

printf '\n%sBundle ready%s\n' "$C_BOLD" "$C_RESET"
printf '    %s\n' "$OUTPUT_DIR"
printf '    %s payload, %s files\n' \
    "$(du -sh "$PUBLISH_DIR" | cut -f1)" \
    "$(find "$PUBLISH_DIR" -type f | wc -l | tr -d ' ')"
cat <<EOF

Next: copy that folder into the Windows guest and run, in an elevated PowerShell,

    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    .\\provision-guest.ps1

EOF
