using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.Versioning;

namespace BfmeFoundationProject.DirectXRuntime
{
    [SupportedOSPlatform("windows")]
    public class DirectXRuntimeManager
    {
        private static readonly string DxRuntimeVersion = "v1";

        /// <summary>
        /// Set to 1/true to skip running the DirectX 9 redistributable entirely, for hosts where
        /// d3dx9 is already provisioned by other means (a Wine prefix set up with winetricks, or
        /// a VM image that has had the redist installed once already). DXSETUP.exe is a legacy
        /// 32-bit x86 installer, so skipping it also avoids running it under emulation on
        /// Windows-on-ARM guests.
        /// </summary>
        public const string SkipVariable = "BFME_SKIP_DX_RUNTIME";

        public static async Task EnsureRuntimes()
        {
            if (IsSkipRequested())
                return;

            await Task.Run(() =>
            {
                string configDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BFME Workshop", "Config");
                string directxDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BFME Workshop", "DirectX");

                if (!Directory.Exists(configDirectory))
                    Directory.CreateDirectory(configDirectory);

                if (!Directory.Exists(directxDirectory))
                    Directory.CreateDirectory(directxDirectory);

                bool installDxRuntime = true;

                if (File.Exists(Path.Combine(configDirectory, "dx_version.flag")))
                {
                    string[] versions = File.ReadAllText(Path.Combine(configDirectory, "dx_version.flag")).Split('\n');

                    if (versions[0] == "" || versions[0] == DxRuntimeVersion)
                        installDxRuntime = false;
                }

                if ((!File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "D3DX9_43.dll")) && !File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "d3dx9_43.dll"))) || (!File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.SystemX86), "D3DX9_43.dll")) && !File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.SystemX86), "d3dx9_43.dll"))))
                    installDxRuntime = true;

                foreach (string resource in Assembly.GetExecutingAssembly().GetManifestResourceNames().Where(x => x.Contains("BfmeFoundationProject.DirectXRuntime.Resources.")))
                {
                    string resourceName = resource.Replace("BfmeFoundationProject.DirectXRuntime.Resources.", "");
                    using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource)!)
                    {
                        if (resourceName == "dx9_redist.zip" && installDxRuntime)
                        {
                            using (FileStream fs = new FileStream(Path.Combine(directxDirectory, resourceName), FileMode.Create, FileAccess.ReadWrite, FileShare.None))
                            {
                                stream.Seek(0, SeekOrigin.Begin);
                                stream.CopyTo(fs);
                            }
                        }
                    }
                }

                if (installDxRuntime)
                {
                    ZipFile.ExtractToDirectory(Path.Combine(directxDirectory, "dx9_redist.zip"), Path.Combine(directxDirectory, "dx9_redist"), true);

                    string dxSetupPath = Path.Combine(directxDirectory, "dx9_redist", "DXSETUP.exe");

                    // Only clear the existing d3dx9_43 copies once we know we actually have an
                    // installer to put them back with, otherwise a failed extract would leave the
                    // system with no d3dx9 at all.
                    if (File.Exists(dxSetupPath))
                    {
                        DeleteSystemD3dx9(Environment.SpecialFolder.System);
                        DeleteSystemD3dx9(Environment.SpecialFolder.SystemX86);

                        Process.Start(new ProcessStartInfo("cmd", $"/C \"{dxSetupPath}\" /silent") { CreateNoWindow = true })!.WaitForExit();
                    }
                }

                File.WriteAllText(Path.Combine(configDirectory, "dx_version.flag"), $"{DxRuntimeVersion}\n0");
            });
        }

        private static bool IsSkipRequested()
        {
            string value = (Environment.GetEnvironmentVariable(SkipVariable) ?? "").Trim();

            return value.Equals("1", StringComparison.OrdinalIgnoreCase)
                || value.Equals("true", StringComparison.OrdinalIgnoreCase)
                || value.Equals("yes", StringComparison.OrdinalIgnoreCase);
        }

        private static void DeleteSystemD3dx9(Environment.SpecialFolder systemFolder)
        {
            try
            {
                string systemDirectory = Environment.GetFolderPath(systemFolder);

                // Casing varies between redist versions and the filesystem may be case sensitive.
                foreach (string fileName in new[] { "D3DX9_43.dll", "d3dx9_43.dll" })
                {
                    string path = Path.Combine(systemDirectory, fileName);

                    if (File.Exists(path))
                        File.Delete(path);
                }
            }
            catch { }
        }
    }
}
