using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows.Media;

namespace BfmeFoundationProject.AllInOneLauncher.Core;

/// <summary>
/// Detects the kind of Windows environment the launcher is running in, and exposes the
/// compatibility switches used when the launcher is hosted somewhere other than a normal
/// physical Windows install (a Windows VM on macOS/Linux, or a Wine/CrossOver prefix).
///
/// Everything here is opt-in: on a regular Windows PC all of these resolve to the
/// stock behaviour, so hosting the launcher elsewhere never costs native users anything.
/// </summary>
internal static class HostEnvironment
{
    /// <summary>Force WPF's render mode. "auto" (default), "software", or "hardware".</summary>
    public const string RenderModeVariable = "BFME_RENDER_MODE";

    /// <summary>Set to 1/true to stop the launcher replacing itself with the official build.</summary>
    public const string DisableSelfUpdateVariable = "BFME_DISABLE_SELF_UPDATE";

    /// <summary>Marker file equivalent of <see cref="DisableSelfUpdateVariable"/>.</summary>
    public const string DisableSelfUpdateMarkerFile = "no-self-update";

    private static readonly Lazy<bool> _isWine = new(DetectWine);

    /// <summary>
    /// True when running on Wine (CrossOver, Whisky, Proton, plain Wine) rather than real Windows.
    /// Detected the canonical way: Wine's ntdll exports wine_get_version, Windows' does not.
    /// </summary>
    public static bool IsWine => _isWine.Value;

    /// <summary>
    /// True when the launcher must not download and exec the official build over itself.
    /// Relevant for any locally built launcher — notably an arm64 build inside a
    /// Windows-on-ARM VM, which the official x64 build would clobber.
    /// </summary>
    public static bool IsSelfUpdateDisabled
    {
        get
        {
            if (IsFlagSet(DisableSelfUpdateVariable))
                return true;

            try
            {
                return File.Exists(Path.Combine(LauncherUpdateManager.LauncherAppDirectory, DisableSelfUpdateMarkerFile));
            }
            catch
            {
                return false;
            }
        }
    }

    /// <summary>
    /// Applies the effective WPF render mode.
    ///
    /// WPF renders through Direct3D 9. Wine's D3D9 implementation is not reliable enough for
    /// WPF's usage of it and typically crashes the process during composition, so Wine gets
    /// software rendering. Real Windows — including a Windows VM, whose virtual GPU still has
    /// a working D3D9 path via the host driver — keeps hardware rendering, because WPF already
    /// degrades to its own software pipeline when no usable device is present.
    /// </summary>
    public static void ApplyRenderMode()
    {
        if (ShouldUseSoftwareRendering())
            RenderOptions.ProcessRenderMode = RenderMode.SoftwareOnly;
    }

    private static bool ShouldUseSoftwareRendering()
    {
        string mode = (Environment.GetEnvironmentVariable(RenderModeVariable) ?? "").Trim();

        if (mode.Equals("software", StringComparison.OrdinalIgnoreCase))
            return true;

        if (mode.Equals("hardware", StringComparison.OrdinalIgnoreCase))
            return false;

        // "auto" / unset: only the environments known to break under hardware WPF.
        return IsWine;
    }

    private static bool IsFlagSet(string variable)
    {
        string value = (Environment.GetEnvironmentVariable(variable) ?? "").Trim();

        return value.Equals("1", StringComparison.OrdinalIgnoreCase)
            || value.Equals("true", StringComparison.OrdinalIgnoreCase)
            || value.Equals("yes", StringComparison.OrdinalIgnoreCase);
    }

    private static bool DetectWine()
    {
        try
        {
            IntPtr ntdll = GetModuleHandle("ntdll.dll");

            return ntdll != IntPtr.Zero && GetProcAddress(ntdll, "wine_get_version") != IntPtr.Zero;
        }
        catch
        {
            return false;
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("kernel32.dll", CharSet = CharSet.Ansi, ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr hModule, string procName);
}
