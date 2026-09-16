using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Security;
using Microsoft.Win32;

namespace Clawdmeter.Platform;

/// Starts Clawdmeter with Windows through the per user Run key. Nothing here needs admin,
/// and if the key cannot be touched the app just carries on without it.
public static class StartupItem
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Clawdmeter";

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
                return key?.GetValue(ValueName) is string value && value.Length > 0;
            }
            catch (Exception exception) when (IsExpected(exception))
            {
                return false;
            }
        }
    }

    public static void SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(KeyPath, true);
            if (key is null) return;
            if (enabled)
            {
                if (ExecutablePath() is not { Length: > 0 } path) return;
                key.SetValue(ValueName, "\"" + path + "\"", RegistryValueKind.String);
            }
            else
            {
                key.DeleteValue(ValueName, false);
            }
        }
        catch (Exception exception) when (IsExpected(exception))
        {
        }
    }

    internal static string? ExecutablePath()
    {
        var path = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(path)) return path;
        try
        {
            using var process = Process.GetCurrentProcess();
            return process.MainModule?.FileName;
        }
        catch (Exception exception) when (IsExpected(exception))
        {
            return null;
        }
    }

    private static bool IsExpected(Exception exception)
        => exception is UnauthorizedAccessException
            or SecurityException
            or IOException
            or ObjectDisposedException
            or NotSupportedException
            or InvalidOperationException
            or Win32Exception;
}
