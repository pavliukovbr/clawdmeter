using System.Diagnostics;
using System.IO;

namespace Clawdmeter.Usage;

/// The Claude desktop app keeps a sign in of its own, so the one Claude Code leaves in its
/// credentials file runs out when the command line has not been used for a few hours.
/// Starting the command line with a local command that never reaches the model is enough
/// for it to renew that sign in by itself. Nothing is sent to Claude and no usage is spent.
public static class SignInRenewal
{
    private static readonly object Gate = new();
    private static DateTimeOffset lastAttempt = DateTimeOffset.MinValue;
    private static readonly TimeSpan MinimumGap = TimeSpan.FromMinutes(10);
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(45);

    /// True when the command line ran, which is the moment to read the sign in again.
    public static async Task<bool> Renew(CancellationToken cancel = default)
    {
        lock (Gate)
        {
            if (DateTimeOffset.Now - lastAttempt < MinimumGap) return false;
            lastAttempt = DateTimeOffset.Now;
        }
        if (CommandLine() is not { } command) return false;

        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = command,
                ArgumentList = { "-p", "/status", "--no-session-persistence" },
                WorkingDirectory = Path.GetTempPath(),
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            });
            if (process is null) return false;
            process.StandardInput.Close();
            _ = process.StandardOutput.ReadToEndAsync(cancel);
            _ = process.StandardError.ReadToEndAsync(cancel);

            using var limit = CancellationTokenSource.CreateLinkedTokenSource(cancel);
            limit.CancelAfter(Timeout);
            try
            {
                await process.WaitForExitAsync(limit.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            }
            return true;
        }
        catch (Exception exception) when (exception is System.ComponentModel.Win32Exception or IOException or InvalidOperationException)
        {
            return false;
        }
    }

    /// Where the installers put it, since a tray app does not always see the latest PATH.
    private static string? CommandLine()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var candidates = new[]
        {
            Path.Combine(home, ".local", "bin", "claude.exe"),
            Path.Combine(appData, "npm", "claude.cmd"),
            Path.Combine(home, ".claude", "local", "claude.exe"),
        };
        return candidates.FirstOrDefault(File.Exists);
    }
}
