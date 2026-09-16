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
    private const long LargestRelease = 2L * 1024 * 1024;
    private const long LargestChecksum = 8L * 1024;
    private const long LargestUnpacked = 500L * 1024 * 1024;
    private const int MostFiles = 4000;
    private const int WaitSeconds = 90;

    private static readonly HttpClient Client = CreateClient();

    private bool automatic;
    private string? announced;
    private int installing;

    /// Raised off the UI thread, so hop back to the dispatcher before touching windows.
    public event Action<UpdateInfo>? UpdateReady;

    /// Called instead of closing the app outright, so the tray icon and the rest go first.
    public Action? Shutdown { get; set; }

    public string CurrentVersion { get; } = ReadCurrentVersion();

    /// A short line to show when the last check or install did not work out.
    public string? LastFailure { get; private set; }

    /// A check the caller asked for. It answers the caller and stays quiet otherwise.
    public Task<UpdateInfo?> Check(CancellationToken cancel = default) => Find(false, cancel);

    private async Task<UpdateInfo?> Find(bool announce, CancellationToken cancel)
    {
        try
        {
            using var response = await Client.GetAsync(LatestUrl, HttpCompletionOption.ResponseHeadersRead, cancel).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                LastFailure = "GitHub answered " + (int)response.StatusCode;
                return null;
            }
            // Redirects are followed for us, so the address that actually answered is checked too.
            if (!IsTrusted(response.RequestMessage?.RequestUri))
            {
                LastFailure = "The release list came from somewhere else";
                return null;
            }
            if (await Body(response, LargestRelease, cancel).ConfigureAwait(false) is not { } json)
            {
                LastFailure = "The release list is bigger than it should be";
                return null;
            }

            using var document = JsonDocument.Parse(new ReadOnlyMemory<byte>(json));
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
            // The same version is found again every few hours, so only say so once. A find the
            // caller asked for is returned and never announced, so one release opens one window.
            var known = announced == version;
            announced = version;
            if (announce && !known) UpdateReady?.Invoke(update);
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
        if (Interlocked.CompareExchange(ref installing, 1, 0) != 0)
        {
            LastFailure = "An update is already being installed";
            return false;
        }

        var done = false;
        try
        {
            done = await Apply(update, cancel).ConfigureAwait(false);
            return done;
        }
        finally
        {
            // After a good swap the app is on its way out, so the door stays shut.
            if (!done) Interlocked.Exchange(ref installing, 0);
        }
    }

    private async Task<bool> Apply(UpdateInfo update, CancellationToken cancel)
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

            // The digest is published in the same release as the archive, so it only shows the
            // download arrived whole. Whoever can replace one asset can replace both. Clawdmeter
            // has no signing certificate, so there is no Authenticode check behind this either.
            var text = await Fetch(update.ChecksumUrl, LargestChecksum, cancel).ConfigureAwait(false);
            var published = text is null ? null : ExpectedDigest(text);
            if (published is null || published != Digest(archive))
            {
                return Failed(work, "The download did not match its checksum, so nothing was installed");
            }

            var unpacked = Path.Combine(work, "app");
            if (!Unpack(archive, unpacked))
            {
                return Failed(work, "The download does not unpack into a sensible app");
            }
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
                // Keep out of the way while a download or a swap is already running.
                if (Settings.Current.UpdateAutomatically && Volatile.Read(ref installing) == 0)
                {
                    await Find(true, default).ConfigureAwait(false);
                }
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
        => Uri.TryCreate(url, UriKind.Absolute, out var uri) && IsTrusted(uri);

    private static bool IsTrusted(Uri? uri)
    {
        if (uri is null) return false;
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
        if (!IsTrusted(response.RequestMessage?.RequestUri)) return false;
        if (response.Content.Headers.ContentLength is > LargestDownload) return false;

        await using var source = await response.Content.ReadAsStreamAsync(cancel).ConfigureAwait(false);
        long total = 0;
        await using (var file = File.Create(destination))
        {
            var chunk = new byte[128 * 1024];
            int read;
            // A body without a length header can still run long, so it is counted as it arrives.
            while ((read = await source.ReadAsync(chunk, cancel).ConfigureAwait(false)) > 0)
            {
                total += read;
                if (total > LargestDownload) return false;
                await file.WriteAsync(chunk.AsMemory(0, read), cancel).ConfigureAwait(false);
            }
        }
        return total > 0;
    }

    private static async Task<string?> Fetch(string url, long most, CancellationToken cancel)
    {
        if (!IsTrusted(url)) return null;
        using var response = await Client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancel).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode) return null;
        if (!IsTrusted(response.RequestMessage?.RequestUri)) return null;
        if (await Body(response, most, cancel).ConfigureAwait(false) is not { } bytes) return null;
        return Encoding.UTF8.GetString(bytes);
    }

    /// Reads a small body, and gives up rather than growing past the cap.
    private static async Task<byte[]?> Body(HttpResponseMessage response, long most, CancellationToken cancel)
    {
        if (response.Content.Headers.ContentLength is { } length && length > most) return null;

        await using var source = await response.Content.ReadAsStreamAsync(cancel).ConfigureAwait(false);
        using var kept = new MemoryStream();
        var chunk = new byte[64 * 1024];
        int read;
        while ((read = await source.ReadAsync(chunk, cancel).ConfigureAwait(false)) > 0)
        {
            if (kept.Length + read > most) return null;
            kept.Write(chunk, 0, read);
        }
        return kept.ToArray();
    }

    private static string Digest(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    /// The published file looks like "digest  name", so keep the first word.
    private static string? ExpectedDigest(string text)
    {
        var token = text.Split([' ', '\t', '\r', '\n', '*', '﻿'], StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
        if (token is not { Length: 64 }) return null;
        return token.All(Uri.IsHexDigit) ? token.ToLowerInvariant() : null;
    }

    // MARK: Install

    /// Unpacks by hand, because a small archive can otherwise ask for a very large folder.
    private static bool Unpack(string archive, string destination)
    {
        Directory.CreateDirectory(destination);
        var root = Path.GetFullPath(destination);
        if (!root.EndsWith(Path.DirectorySeparatorChar)) root += Path.DirectorySeparatorChar;

        using var zip = ZipFile.OpenRead(archive);
        if (zip.Entries.Count > MostFiles) return false;

        long total = 0;
        var buffer = new byte[128 * 1024];
        foreach (var entry in zip.Entries)
        {
            var target = Path.GetFullPath(Path.Combine(destination, entry.FullName));
            // Entry names are allowed to say anything, including a path outside the folder.
            if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) return false;

            if (entry.Name.Length == 0)
            {
                Directory.CreateDirectory(target);
                continue;
            }
            if (Path.GetDirectoryName(target) is not { Length: > 0 } holder) return false;
            if (entry.Length < 0 || total + entry.Length > LargestUnpacked) return false;

            Directory.CreateDirectory(holder);
            using var source = entry.Open();
            using var file = File.Create(target);
            int read;
            while ((read = source.Read(buffer, 0, buffer.Length)) > 0)
            {
                total += read;
                if (total > LargestUnpacked) return false;
                file.Write(buffer, 0, read);
            }
        }
        return true;
    }

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
        if (!File.Exists(executable)) return false;
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

    /// Every path out of here leaves a working Clawdmeter behind: either the new one, or the
    /// old one back in place and running again. Nothing in the install folder is ever deleted.
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
            set "spare={backup}\{ExecutableName}"
            set "code=1"
            set /a tries=0

            if not exist "%source%\{ExecutableName}" goto leave

            :wait
            tasklist /fi "pid eq {id}" /nh | find "{id}" >nul
            if errorlevel 1 goto ready
            set /a tries+=1
            if %tries% geq {WaitSeconds} goto leave
            timeout /t 1 /nobreak >nul
            goto wait

            :ready
            robocopy "%target%" "%backup%" /e /r:1 /w:1 /njh /njs /ndl /nfl /nc /ns >nul
            rem Without a copy of the old build there is no way back, so nothing is replaced.
            if not exist "%spare%" goto relaunch

            robocopy "%source%" "%target%" /e /r:2 /w:1 /njh /njs /ndl /nfl /nc /ns >nul
            if errorlevel 8 goto restore
            if not exist "%app%" goto restore
            set "code=0"
            start "" "%app%"
            goto leave

            :restore
            rem Plain copy, never a mirror, so whatever else lives in that folder is left alone.
            robocopy "%backup%" "%target%" /e /r:2 /w:1 /njh /njs /ndl /nfl /nc /ns >nul

            :relaunch
            start "" "%app%"

            :leave
            rd /s /q "%work%" >nul 2>&1
            del "%~f0" >nul 2>&1
            exit /b %code%

            """;
    }

    /// The script keeps paths in quoted variables, so these would break it.
    private static bool IsAwkward(string path)
        => path.Length == 0
            || path.Contains('"')
            || path.Contains('%')
            || path.Contains('\r')
            || path.Contains('\n');

    private void Quit()
    {
        var app = System.Windows.Application.Current;
        if (app is null)
        {
            Leave();
            return;
        }
        try
        {
            app.Dispatcher.BeginInvoke(new Action(Leave));
        }
        catch (InvalidOperationException)
        {
        }
        catch (TaskCanceledException)
        {
        }
    }

    private void Leave()
    {
        try
        {
            if (Shutdown is { } hook)
            {
                hook();
                return;
            }
        }
        catch (Exception exception) when (IsExpected(exception))
        {
            // The app still has to close, so fall through to the plain way out.
        }
        try
        {
            System.Windows.Application.Current?.Shutdown();
        }
        catch (Exception exception) when (IsExpected(exception))
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
        var handler = new SocketsHttpHandler
        {
            AllowAutoRedirect = true,
            MaxAutomaticRedirections = 5,
        };
        var client = new HttpClient(handler) { Timeout = TimeSpan.FromMinutes(5) };
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
