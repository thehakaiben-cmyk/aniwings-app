using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

namespace AniWingsLauncher
{
    static class Program
    {
        private const string AppVersion = "__APP_VERSION__";
        private const string MainExeName = "aniwings.exe";

        [STAThread]
        static void Main(string[] args)
        {
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string appDir = Path.Combine(localAppData, "AniWings", "app");
                string versionFile = Path.Combine(appDir, ".version");
                string targetExe = Path.Combine(appDir, MainExeName);

                bool needsExtract = true;
                if (Directory.Exists(appDir) && File.Exists(versionFile) && File.Exists(targetExe))
                {
                    try
                    {
                        string installedVersion = File.ReadAllText(versionFile).Trim();
                        if (installedVersion == AppVersion)
                        {
                            needsExtract = false;
                        }
                    }
                    catch
                    {
                        needsExtract = true;
                    }
                }

                if (needsExtract)
                {
                    Process[] running = Process.GetProcessesByName(Path.GetFileNameWithoutExtension(MainExeName));
                    if (running.Length > 0)
                    {
                        foreach (var p in running)
                        {
                            try
                            {
                                if (p.MainModule != null && p.MainModule.FileName.StartsWith(appDir, StringComparison.OrdinalIgnoreCase))
                                {
                                    MessageBox.Show(
                                        "AniWings is currently running. Please close the running instance to complete the update.",
                                        "AniWings Update",
                                        MessageBoxButtons.OK,
                                        MessageBoxIcon.Warning
                                    );
                                    return;
                                }
                            }
                            catch
                            {
                                // Ignore permission errors on foreign processes
                            }
                        }
                    }

                    Directory.CreateDirectory(appDir);
                    var assembly = Assembly.GetExecutingAssembly();
                    using (Stream stream = assembly.GetManifestResourceStream("bundle.zip"))
                    {
                        if (stream == null)
                        {
                            MessageBox.Show(
                                "Corrupted executable: embedded application bundle is missing.",
                                "AniWings Error",
                                MessageBoxButtons.OK,
                                MessageBoxIcon.Error
                            );
                            return;
                        }

                        using (ZipArchive archive = new ZipArchive(stream, ZipArchiveMode.Read))
                        {
                            foreach (ZipArchiveEntry entry in archive.Entries)
                            {
                                string destinationPath = Path.GetFullPath(Path.Combine(appDir, entry.FullName));
                                if (!destinationPath.StartsWith(appDir, StringComparison.OrdinalIgnoreCase))
                                {
                                    continue;
                                }

                                if (string.IsNullOrEmpty(entry.Name))
                                {
                                    Directory.CreateDirectory(destinationPath);
                                }
                                else
                                {
                                    string dir = Path.GetDirectoryName(destinationPath);
                                    if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                                    {
                                        Directory.CreateDirectory(dir);
                                    }
                                    entry.ExtractToFile(destinationPath, true);
                                }
                            }
                        }
                    }

                    File.WriteAllText(versionFile, AppVersion);
                }

                if (!File.Exists(targetExe))
                {
                    MessageBox.Show(
                        "Failed to locate application executable after extraction: " + targetExe,
                        "AniWings Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    return;
                }

                ProcessStartInfo startInfo = new ProcessStartInfo
                {
                    FileName = targetExe,
                    WorkingDirectory = appDir,
                    Arguments = string.Join(" ", args),
                    UseShellExecute = true
                };

                Process.Start(startInfo);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Error launching AniWings:\n\n" + ex.Message,
                    "AniWings Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
        }
    }
}
