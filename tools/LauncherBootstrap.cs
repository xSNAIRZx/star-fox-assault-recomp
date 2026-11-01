using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

internal static class LauncherBootstrap
{
    [STAThread]
    private static int Main()
    {
        string appDirectory = Path.GetDirectoryName(Application.ExecutablePath);
        string scriptPath = Path.Combine(appDirectory, "Launch-StarFoxAssault.ps1");
        if (!File.Exists(scriptPath))
        {
            MessageBox.Show(
                "Launch-StarFoxAssault.ps1 was not found beside this application. Restore the launcher files and try again.",
                "Star Fox Assault Recomp",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }

        string windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string powershellPath = Path.Combine(windowsDirectory, "System32\\WindowsPowerShell\\v1.0\\powershell.exe");
        if (!File.Exists(powershellPath))
        {
            MessageBox.Show(
                "Windows PowerShell could not be found. The launcher needs the Windows PowerShell 5.1 component.",
                "Star Fox Assault Recomp",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }

        ProcessStartInfo start = new ProcessStartInfo();
        start.FileName = powershellPath;
        start.Arguments = "-NoProfile -NoLogo -STA -ExecutionPolicy Bypass -File " + QuoteArgument(scriptPath);
        start.WorkingDirectory = appDirectory;
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.WindowStyle = ProcessWindowStyle.Normal;

        try
        {
            Process child = Process.Start(start);
            if (child == null)
            {
                throw new InvalidOperationException("Windows PowerShell did not start.");
            }
            child.Dispose();
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "The launcher could not start Windows PowerShell.\r\n\r\n" + ex.Message,
                "Star Fox Assault Recomp",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string QuoteArgument(string value)
    {
        StringBuilder quoted = new StringBuilder();
        quoted.Append('"');
        int backslashes = 0;
        for (int i = 0; i < value.Length; i++)
        {
            char c = value[i];
            if (c == '\\')
            {
                backslashes++;
            }
            else if (c == '"')
            {
                quoted.Append('\\', backslashes * 2 + 1);
                quoted.Append('"');
                backslashes = 0;
            }
            else
            {
                quoted.Append('\\', backslashes);
                quoted.Append(c);
                backslashes = 0;
            }
        }
        quoted.Append('\\', backslashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }
}
