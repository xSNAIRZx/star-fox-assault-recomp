using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

internal static class LauncherBootstrap
{
    private const string ProductTitle = "Peregrine Forge | Star Fox Assault Recomp";

    [STAThread]
    private static int Main(string[] args)
    {
        // RecompLauncher's windowless modes (see RecompLauncherMode below). Without these
        // arguments the bootstrap opens the Peregrine Forge launcher exactly as before.
        if (args.Length > 0 && args[0] == "--prepare") { return RecompLauncherMode.Prepare(args); }
        if (args.Length > 0 && args[0] == "--play") { return RecompLauncherMode.Play(args); }

        string appDirectory = Path.GetDirectoryName(Application.ExecutablePath);
        string scriptPath = Path.Combine(appDirectory, "Launch-StarFoxAssault.ps1");
        if (!File.Exists(scriptPath))
        {
            MessageBox.Show(
                "Launch-StarFoxAssault.ps1 was not found beside this application. Restore the launcher files and try again.",
                ProductTitle,
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
                ProductTitle,
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
                ProductTitle,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }

    internal static string QuoteArgument(string value)
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

// Windowless modes for RecompLauncher (recomplauncher.json at the package root). They reuse the
// existing build worker and start the game the way Launch-StarFoxAssault.ps1 does, so saves,
// logs and the build record stay where the Peregrine Forge launcher keeps them.
//
//   --prepare --game <image>      runs tools/Build-StarFoxAssault.ps1 and prints
//                                 "progress <0..1> <text>" lines; exits with the worker's code.
//   --play --game <image> [args]  starts build-desktop/Release/assault.exe in user-data/native-run
//                                 with the launcher's GCN_* variables, waits for it and returns
//                                 its exit code. Extra arguments go to the game before the image.
internal static class RecompLauncherMode
{
    // Explained to the player by "exit_codes" in recomplauncher.json.
    private const int ExitNotBuilt = 3;
    private const int ExitOtherCopy = 4;
    private const int ExitMissing = 5;
    private const string GameId = "GF7E01";

    private static IntPtr killOnCloseJob = IntPtr.Zero;

    internal static int Prepare(string[] args)
    {
        List<string> rest;
        string game = ReadGameArgument(args, out rest);
        if (game == null || !File.Exists(game))
        {
            Console.Error.WriteLine("Pass the path of your USA .iso or .ciso with --game.");
            return ExitMissing;
        }
        string project = ProjectDirectory();
        string script = Path.Combine(project, "tools\\Build-StarFoxAssault.ps1");
        string powershell = PowerShellPath();
        if (!File.Exists(script) || !File.Exists(powershell))
        {
            Console.Error.WriteLine("The build script or Windows PowerShell is missing. Reinstall the recomp.");
            return ExitMissing;
        }
        // The same job folder layout the launcher's Import & Build uses.
        string jobId = DateTime.Now.ToString("yyyyMMdd-HHmmss-fff", CultureInfo.InvariantCulture) + "-" + Guid.NewGuid().ToString("N");
        string jobDir = Path.Combine(project, "user-data\\build-jobs\\" + jobId);
        Directory.CreateDirectory(jobDir);
        string statusPath = Path.Combine(jobDir, "status.json");

        ProcessStartInfo start = new ProcessStartInfo();
        start.FileName = powershell;
        start.Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + LauncherBootstrap.QuoteArgument(script) +
            " -GameImage " + LauncherBootstrap.QuoteArgument(Path.GetFullPath(game)) +
            " -UsePortableToolchain -ProgressFile " + LauncherBootstrap.QuoteArgument(statusPath);
        start.WorkingDirectory = project;
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.RedirectStandardOutput = true;
        start.RedirectStandardError = true;
        start.EnvironmentVariables["STARFOX_ASSAULT_PORTABLE"] = "1";

        Console.WriteLine("progress 0 Checking your disc image");
        using (StreamWriter stdout = new StreamWriter(Path.Combine(jobDir, "stdout.log"), false, new UTF8Encoding(false)))
        using (StreamWriter stderr = new StreamWriter(Path.Combine(jobDir, "stderr.log"), false, new UTF8Encoding(false)))
        using (Process build = StartLogged(start, stdout, stderr))
        {
            double shown = 0;
            string lastText = null;
            string lastMessage = null;
            while (!build.WaitForExit(250))
            {
                ReportProgress(statusPath, ref shown, ref lastText, ref lastMessage);
            }
            build.WaitForExit();
            ReportProgress(statusPath, ref shown, ref lastText, ref lastMessage);
            if (build.ExitCode != 0 && lastMessage != null)
            {
                Console.Error.WriteLine(lastMessage);
            }
            return build.ExitCode;
        }
    }

    internal static int Play(string[] args)
    {
        List<string> rest;
        string game = ReadGameArgument(args, out rest);
        string project = ProjectDirectory();
        string exe = Path.Combine(project, "build-desktop\\Release\\assault.exe");
        if (!File.Exists(exe))
        {
            Console.Error.WriteLine("The game has not been built from your disc yet.");
            return ExitNotBuilt;
        }
        if (game == null || !File.Exists(game))
        {
            Console.Error.WriteLine("Your copy of the game was not found.");
            return ExitMissing;
        }
        if (!BuildMatchesImage(project, exe, game))
        {
            Console.Error.WriteLine("This build was made from a different copy of the game.");
            return ExitOtherCopy;
        }

        string runDir = Path.Combine(project, "user-data\\native-run");
        string logsDir = Path.Combine(runDir, "logs");
        Directory.CreateDirectory(logsDir);
        string session = "native-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff", CultureInfo.InvariantCulture) + "-" + Guid.NewGuid().ToString("N").Substring(0, 6);

        List<string> gameArgs = new List<string>(rest);
        // Big Picture mode is played from the couch: start full screen there.
        if (Environment.GetEnvironmentVariable("RECOMPLAUNCHER_MODE") == "bigpicture" && !gameArgs.Contains("--fullscreen"))
        {
            gameArgs.Add("--fullscreen");
        }
        StringBuilder line = new StringBuilder();
        foreach (string argument in gameArgs)
        {
            line.Append(LauncherBootstrap.QuoteArgument(argument)).Append(' ');
        }
        line.Append(LauncherBootstrap.QuoteArgument(Path.GetFullPath(game)));

        ProcessStartInfo start = new ProcessStartInfo();
        start.FileName = exe;
        start.Arguments = line.ToString();
        start.WorkingDirectory = runDir;
        start.UseShellExecute = false;
        start.CreateNoWindow = true;
        start.RedirectStandardOutput = true;
        start.RedirectStandardError = true;
        // The same variables as Get-NativeSessionEnvironment in tools/LauncherNative.ps1.
        start.EnvironmentVariables["GCN_TIMESCALE"] = "1";
        start.EnvironmentVariables["GCN_CLOCKLOG"] = "1";
        start.EnvironmentVariables.Remove("GCN_INPUT");
        start.EnvironmentVariables["GCN_RAM_DUMP"] = Path.Combine(logsDir, session + ".ram.bin");
        start.EnvironmentVariables["GCN_WATCH_ADDR"] = "800000E4";
        start.EnvironmentVariables["GCN_GUARD"] = "800000E4";
        start.EnvironmentVariables["GCN_FONT_DIR"] = Path.Combine(project, "assets\\fonts");
        start.EnvironmentVariables.Remove("GCN_MODS_DIR");

        using (StreamWriter stdout = new StreamWriter(Path.Combine(logsDir, session + ".log"), false, new UTF8Encoding(false)))
        using (StreamWriter stderr = new StreamWriter(Path.Combine(logsDir, session + ".err"), false, new UTF8Encoding(false)))
        using (Process gameProcess = StartLogged(start, stdout, stderr))
        {
            gameProcess.WaitForExit();
            return gameProcess.ExitCode;
        }
    }

    // --game <path> or --game=<path>; every other argument after the mode is returned in rest.
    private static string ReadGameArgument(string[] args, out List<string> rest)
    {
        rest = new List<string>();
        string game = null;
        for (int i = 1; i < args.Length; i++)
        {
            if (args[i] == "--game" && i + 1 < args.Length) { game = args[++i]; }
            else if (args[i].StartsWith("--game=", StringComparison.Ordinal)) { game = args[i].Substring(7); }
            else { rest.Add(args[i]); }
        }
        return string.IsNullOrEmpty(game) ? null : game;
    }

    private static string ProjectDirectory()
    {
        return Path.GetDirectoryName(Application.ExecutablePath);
    }

    private static string PowerShellPath()
    {
        string windowsDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        return Path.Combine(windowsDirectory, "System32\\WindowsPowerShell\\v1.0\\powershell.exe");
    }

    // Starts a process with its output copied to two files, in a job that ends it if this
    // process is closed (RecompLauncher stopping the game or cancelling setup).
    private static Process StartLogged(ProcessStartInfo start, StreamWriter stdout, StreamWriter stderr)
    {
        Process process = new Process();
        process.StartInfo = start;
        process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) { lock (stdout) { stdout.WriteLine(e.Data); stdout.Flush(); } } };
        process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { if (e.Data != null) { lock (stderr) { stderr.WriteLine(e.Data); stderr.Flush(); } } };
        process.Start();
        KillWithThisProcess(process);
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        return process;
    }

    // Reads the worker's status.json and prints a progress line when it changes. The overall
    // fraction follows the launcher's build dialog (Get-BuildOverallPercent in LauncherCore.ps1).
    private static void ReportProgress(string statusPath, ref double shown, ref string lastText, ref string lastMessage)
    {
        string json;
        try
        {
            using (FileStream stream = new FileStream(statusPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (StreamReader reader = new StreamReader(stream))
            {
                json = reader.ReadToEnd();
            }
        }
        catch (IOException) { return; }
        catch (UnauthorizedAccessException) { return; }
        string phase;
        string message;
        try
        {
            phase = JsonString(json, "phase");
            message = JsonString(json, "message");
        }
        catch (ArgumentException) { return; }
        if (phase == null) { return; }
        double raw = Math.Max(0, Math.Min(100, JsonNumber(json, "percent", 0)));
        double fraction;
        switch (phase)
        {
            case "Checking image": fraction = 0.02; break;
            case "Preparing tools":
            case "Preparing build tools": fraction = 0.05; break;
            case "Recompiling game": fraction = 0.35 + raw * 0.0030; break;
            case "Using build cache": fraction = 0.65; break;
            case "Compiling native executable": fraction = 0.68 + raw * 0.0025; break;
            case "Installing native build": fraction = 0.95; break;
            case "Ready to play": fraction = 1.0; break;
            default: fraction = shown; break;
        }
        if (message != null) { lastMessage = message; }
        shown = Math.Max(shown, fraction);
        string text = phase + (message != null ? ": " + message : "");
        text = text.Replace('\r', ' ').Replace('\n', ' ');
        if (text == lastText) { return; }
        lastText = text;
        Console.WriteLine("progress " + shown.ToString("0.000", CultureInfo.InvariantCulture) + " " + text);
    }

    // The same check as Test-NativeBuildForImage in tools/LauncherNative.ps1: the build record
    // must name this image (path, size, write time), this game and this executable's hash.
    private static bool BuildMatchesImage(string project, string exe, string image)
    {
        try
        {
            string json = File.ReadAllText(Path.Combine(project, "user-data\\native-build-info.json"));
            FileInfo info = new FileInfo(image);
            string recordedImage = JsonString(json, "image");
            string recordedHash = JsonString(json, "executable_sha256");
            if (JsonNumber(json, "schema_version", 0) < 2 || recordedImage == null || recordedHash == null) { return false; }
            if (!string.Equals(Path.GetFullPath(recordedImage), info.FullName, StringComparison.OrdinalIgnoreCase)) { return false; }
            if ((long)JsonNumber(json, "image_size", -1) != info.Length) { return false; }
            if ((long)JsonNumber(json, "image_modified_utc_ticks", -1) != info.LastWriteTimeUtc.Ticks) { return false; }
            if (JsonString(json, "game_id") != GameId) { return false; }
            using (FileStream stream = File.OpenRead(exe))
            using (SHA256 sha = SHA256.Create())
            {
                string hash = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
                return string.Equals(hash, recordedHash, StringComparison.OrdinalIgnoreCase);
            }
        }
        catch (Exception) { return false; }
    }

    // The build files are flat JSON written by ConvertTo-Json, so a field can be read by name.
    private static string JsonString(string json, string name)
    {
        Match match = Regex.Match(json, "\"" + Regex.Escape(name) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
        return match.Success ? Regex.Unescape(match.Groups[1].Value) : null;
    }

    private static double JsonNumber(string json, string name, double fallback)
    {
        Match match = Regex.Match(json, "\"" + Regex.Escape(name) + "\"\\s*:\\s*(-?[0-9][0-9.eE+-]*)");
        double value;
        if (match.Success && double.TryParse(match.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out value)) { return value; }
        return fallback;
    }

    // Best effort: if the job cannot be made, the process still runs normally.
    private static void KillWithThisProcess(Process process)
    {
        try
        {
            if (killOnCloseJob == IntPtr.Zero)
            {
                IntPtr job = CreateJobObject(IntPtr.Zero, null);
                if (job == IntPtr.Zero) { return; }
                JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, ref limits, (uint)Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)))) { CloseHandle(job); return; }
                killOnCloseJob = job;
            }
            AssignProcessToJobObject(killOnCloseJob, process.Handle);
        }
        catch (Exception) { }
    }

    private const int JobObjectExtendedLimitInformation = 9;
    private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct IO_COUNTERS
    {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, uint length);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);
}
