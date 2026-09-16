using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Clawdmeter.Platform;

/// A newer build waiting on GitHub.
public sealed record UpdateInfo(string Version, string Notes, string DownloadUrl, string ChecksumUrl, string PageUrl);

/// Installs new versions from the GitHub releases of this project. It only reads the public
/// release list and downloads the two files below; nothing about you or your PC is sent.
public sealed class Updater
{
    public const string ArchiveName = "Clawdmeter-Windows.zip";
    public const string ChecksumName = ArchiveName + ".sha256";

    private const string LatestUrl = "https://api.github.com/repos/pavliukovbr/clawdmeter/releases/latest";
    private const string ExecutableName = "Clawdmeter.exe";
    private const long LargestDownload = 300L * 1024 * 1024;

    private static readonly HttpClient Client = CreateClient();

    private bool automatic;
    private string? announced;

    /// Raised off the UI thread, so hop back to the dispatcher before touching windows.
    public event Action<UpdateInfo>? UpdateReady;

    public string CurrentVersion { get; } = ReadCurrentVersion();

    /// A short line to show when the last check or install did not work out.
    public string? LastFailure { get; private set; }

    public async Task<UpdateInfo?> Check(CancellationToken cancel = default)
    {
        try
        {
            using var response = await Client.GetAsync(LatestUrl, cancel).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                LastFailure = "GitHub answered " + (int)response.StatusCode;
                return null;
            }

            var stream = await response.Content.ReadAsStreamAsync(cancel).ConfigureAwait(false);
            using var document = await JsonDocument.ParseAsync(stream, default, cancel).ConfigureAwait(false);
            var root = document.RootElement;

            if (Text(root, "tag_name") is not { Length: > 0 } tag) return null;
            var version = tag.TrimStart('v', 'V');
            if (!IsNewer(version, CurrentVersion))
            {
                LastFailure = null;
                return null;
            }

            var (archive, checksum) = Assets(root);
            if (archive is null || checksum is null)
            {
                LastFailure = "That release has no Windows build yet";
                return null;
            }

            var update = new UpdateInfo(version, Text(root, "body") ?? "", archive, checksum, Text(root, "html_url") ?? "");
            LastFailure = null;
            // The same version is found again every few hours, so only say so once.
            if (announced != version)
            {
                announced = version;
                UpdateReady?.Invoke(update);
            }
            return update;
        }
        catch (Exception exception) when (IsExpected(exception))
        {
            LastFailure = "Could not reach GitHub";
            return null;
        }
    }

    public async Task<bool> Install(UpdateInfo update, CancellationToken cancel = default)
    {
        var work = Path.Combine(Path.GetTempPath(), "ClawdmeterUpdate-" + Guid.NewGuid().ToString("N"));
        try
        {
            if (StartupItem.ExecutablePath() is not { Length: > 0 } running
                || Path.GetDirectoryName(running) is not { Length: > 0 } installed)
            {
                return Failed(work, "Clawdmeter could not find where it is installed");
            }
            if (!IsTrusted(update.ChecksumUrl))
            {
                return Failed(work, "That release does not publish a checksum");
            }

            Directory.CreateDirectory(work);

            var archive = Path.Combine(work, ArchiveName);
            if (!await Download(update.DownloadUrl, archive, cancel).ConfigureAwait(false))
            {
                return Failed(work, "The download did not finish");
            }

            var published = ExpectedDigest(await Client.GetStringAsync(update.ChecksumUrl, cancel).ConfigureAwait(false));
            if (published is null || published != Digest(archive))
            {
                return Failed(work, "The download did not match its checksum, so nothing was installed");
            }

            var unpacked = Path.Combine(work, "app");
            ZipFile.ExtractToDirectory(archive, unpacked);
            if (Payload(unpacked) is not { } folder)
            {
                return Failed(work, "The download is missing " + ExecutableName);
            }
            if (!SameVersion(Path.Combine(folder, ExecutableName), update.Version))
            {
                return Failed(work, "The download is not version " + update.Version);
            }

            if (!Swap(folder, installed, work))
            {
                return Failed(work, "The update could not be installed");
            }

            LastFailure = null;
            Quit();
            return true;
        }
        catch (Exception exception) when (IsExpected(exception))
        {
            return Failed(work, "The update could not be installed");
        }
    }

    private bool Failed(string work, string reason)
    {
        LastFailure = reason;
        Clean(work);
        return false;
    }

    /// One check a minute after launch, then once every six hours.
    public void StartAutomaticChecks()
    {
        if (automatic) return;
        automatic = true;
        _ = Loop();
    }

    private async Task Loop()
    {
        var wait = TimeSpan.FromMinutes(1);
        while (true)
        {
            try
            {
                await Task.Delay(wait).ConfigureAwait(false);
                if (Settings.Current.UpdateAutomatically) await Check().ConfigureAwait(false);
            }
            catch (Exception exception) when (IsExpected(exception))
            {
            }
            wait = TimeSpan.FromHours(6);
        }
    }

    // MARK: Release list

    private static (string? Archive, string? Checksum) Assets(JsonElement release)
    {
        string? archive = null;
        string? checksum = null;
        if (!release.TryGetProperty("assets", out var assets) || assets.ValueKind != JsonValueKind.Array)
        {
            return (null, null);
        }
        foreach (var asset in assets.EnumerateArray())
        {
            var url = Text(asset, "browser_download_url");
            if (url is null || !IsTrusted(url)) continue;
            switch (Text(asset, "name"))
            {
                case ArchiveName:
                    archive = url;
                    break;
                case ChecksumName:
                    checksum = url;
                    break;
            }
        }
        return (archive, checksum);
    }

    /// Only the release files themselves, never a link pointing somewhere else.
    private static bool IsTrusted(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;
        if (uri.Scheme != Uri.UriSchemeHttps) return false;
        var host = uri.Host;
        return host.Equals("github.com", StringComparison.OrdinalIgnoreCase)
            || host.EndsWith(".github.com", StringComparison.OrdinalIgnoreCase)
            || host.EndsWith(".githubusercontent.com", StringComparison.OrdinalIgnoreCase);
    }

    // MARK: Download

    private static async Task<bool> Download(string url, string destination, CancellationToken cancel)
    {
        if (!IsTrusted(url)) return false;
        using var response = await Client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancel).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode) return false;
        if (response.Content.Headers.ContentLength is > LargestDownload) return false;

        await using var source = await response.Content.ReadAsStreamAsync(cancel).ConfigureAwait(false);
        await using (var file = File.Create(destination))
        {
            await source.CopyToAsync(file, cancel).ConfigureAwait(false);
        }
        var size = new FileInfo(destination).Length;
        return size > 0 && size <= LargestDownload;
    }

    private static string Digest(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    /// The published file looks like "digest  name", so keep the first word.
    private static string? ExpectedDigest(string text)
    {
        var token = text.Split([' ', '\t', '\r', '\n', '*'], StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        if (token is not { Length: 64 }) return null;
        return token.All(Uri.IsHexDigit) ? token.ToLowerInvariant() : null;
    }

    // MARK: Install

    /// The archive may hold the app at its root or inside one folder.
    private static string? Payload(string unpacked)
    {
        if (File.Exists(Path.Combine(unpacked, ExecutableName))) return unpacked;
        foreach (var folder in Directory.EnumerateDirectories(unpacked))
        {
            if (File.Exists(Path.Combine(folder, ExecutableName))) return folder;
        }
        return null;
    }

    private static bool SameVersion(string executable, string version)
    {
        var info = FileVersionInfo.GetVersionInfo(executable);
        return Matches(info.FileVersion, version) || Matches(info.ProductVersion, version);
    }

    private static bool Matches(string? candidate, string version)
    {
        if (candidate is null) return false;
        var left = Numbers(candidate);
        var right = Numbers(version);
        if (left.Count == 0 || right.Count == 0) return false;
        for (var index = 0; index < Math.Max(left.Count, right.Count); index++)
        {
            if (At(left, index) != At(right, index)) return false;
        }
        return true;
    }

    /// Hands the swap to a small script, because we cannot replace ourselves while running.
    private static bool Swap(string source, string installed, string work)
    {
        if (IsAwkward(source) || IsAwkward(installed) || IsAwkward(work)) return false;

        var script = Path.Combine(Path.GetTempPath(), "ClawdmeterUpdate-" + Guid.NewGuid().ToString("N") + ".cmd");
        var backup = Path.Combine(work, "previous");
        if (IsAwkward(script) || IsAwkward(backup)) return false;

        File.WriteAllText(script, Script(source, installed, work, backup), new UTF8Encoding(false));

        var start = new ProcessStartInfo
        {
            FileName = script,
            UseShellExecute = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            WorkingDirectory = Path.GetTempPath(),
        };
        Process.Start(start)?.Dispose();
        return true;
    }

    private static string Script(string source, string installed, string work, string backup)
    {
        using var process = Process.GetCurrentProcess();
        var id = process.Id.ToString(CultureInfo.InvariantCulture);
        var executable = Path.Combine(installed, ExecutableName);

        return $"""
            @echo off
            chcp 65001 >nul
            setlocal
            set "source={source}"
            set "target={installed}"
            set "backup={backup}"
            set "work={work}"
            set "app={executable}"
            set /a tries=0

            :wait
            tasklist /fi "pid eq {id}" /nh | find "{id}" >nul
            if errorlevel 1 goto ready
            set /a tries+=1
            if %tries% geq 90 goto ready
            timeout /t 1 /nobreak >nul
            goto wait

            :ready
            robocopy "%target%" "%backup%" /mir /r:1 /w:1 /njh /njs /ndl /nfl /nc /ns >nul
            robocopy "%source%" "%target%" /mir /r:2 /w:1 /njh /njs /ndl /nfl /nc /ns >nul
            if errorlevel 8 goto restore
            start "" "%app%"
            rd /s /q "%work%" >nul 2>&1
            del "%~f0" >nul 2>&1
            exit /b 0

            :restore
            robocopy "%backup%" "%target%" /mir /r:2 /w:1 /njh /njs /ndl /nfl /nc /ns >nul
            start "" "%app%"
            rd /s /q "%work%" >nul 2>&1
            del "%~f0" >nul 2>&1
            exit /b 1

            """;
    }

    /// The script keeps paths in quoted variables, so these two would break it.
    private static bool IsAwkward(string path)
        => path.Length == 0 || path.Contains('"') || path.Contains('%');

    private static void Quit()
    {
        var app = System.Windows.Application.Current;
        if (app is null) return;
        try
        {
            app.Dispatcher.BeginInvoke(new Action(() => System.Windows.Application.Current?.Shutdown()));
        }
        catch (InvalidOperationException)
        {
        }
        catch (TaskCanceledException)
        {
        }
    }

    private static void Clean(string folder)
    {
        try
        {
            if (Directory.Exists(folder)) Directory.Delete(folder, true);
        }
        catch (Exception exception) when (IsExpected(exception))
        {
        }
    }

    // MARK: Versions

    public static bool IsNewer(string candidate, string current)
    {
        var left = Numbers(candidate);
        var right = Numbers(current);
        for (var index = 0; index < Math.Max(left.Count, right.Count); index++)
        {
            var a = At(left, index);
            var b = At(right, index);
            if (a != b) return a > b;
        }
        return false;
    }

    private static List<int> Numbers(string version)
    {
        var parts = new List<int>();
        foreach (var piece in version.Split('.', '-', '+', ' '))
        {
            if (!int.TryParse(piece, NumberStyles.None, CultureInfo.InvariantCulture, out var number)) break;
            parts.Add(number);
        }
        return parts;
    }

    private static int At(List<int> parts, int index) => index < parts.Count ? parts[index] : 0;

    private static string ReadCurrentVersion()
    {
        var version = Assembly.GetEntryAssembly()?.GetName().Version ?? Assembly.GetExecutingAssembly().GetName().Version;
        return version is null ? "0" : $"{version.Major}.{version.Minor}.{version.Build}";
    }

    // MARK: Plumbing

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("Clawdmeter", "1.0"));
        client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        return client;
    }

    private static string? Text(JsonElement element, string name)
        => element.ValueKind == JsonValueKind.Object
           && element.TryGetProperty(name, out var value)
           && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static bool IsExpected(Exception exception)
        => exception is HttpRequestException
            or OperationCanceledException
            or JsonException
            or IOException
            or InvalidDataException
            or UnauthorizedAccessException
            or NotSupportedException
            or ObjectDisposedException
            or InvalidOperationException
            or SecurityException
            or Win32Exception
            or ArgumentException
            or FormatException;
}
