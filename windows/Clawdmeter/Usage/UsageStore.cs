using System.IO;
using System.Net.Http;
using System.Text.Json;
using Microsoft.Win32;

namespace Clawdmeter.Usage;

/// Keeps the current picture of your plan: asks Anthropic every few minutes, counts the
/// local logs, and hands the result to whoever is showing it.
public sealed class UsageStore : IDisposable
{
    private readonly ActivityScanner scanner = new();
    private readonly System.Timers.Timer timer = new(TimeSpan.FromMinutes(5).TotalMilliseconds);
    private readonly SemaphoreSlim gate = new(1, 1);

    public UsageSnapshot? Snapshot { get; private set; }

    public event Action<UsageSnapshot>? Updated;

    private static string SnapshotPath => Path.Combine(Settings.Folder, "usage.json");

    public UsageStore()
    {
        Snapshot = LoadCached();
        timer.Elapsed += (_, _) => _ = Refresh();
        timer.AutoReset = true;
        SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    public void Start()
    {
        timer.Start();
        _ = Refresh();
    }

    public async Task Refresh(CancellationToken cancel = default)
    {
        try
        {
            await RefreshInner(cancel).ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            // A bad log line or a locked file is not worth taking the app down for.
            Commit(Keep(Snapshot?.Activity, SnapshotStatus.Offline));
        }
    }

    private async Task RefreshInner(CancellationToken cancel)
    {
        if (!await gate.WaitAsync(0, cancel).ConfigureAwait(false)) return;
        try
        {
            var activity = scanner.Scan(DateTimeOffset.Now);
            var credentials = CredentialsReader.Read();
            if (credentials is null)
            {
                Commit(new UsageSnapshot
                {
                    UpdatedAt = DateTimeOffset.Now,
                    Plan = Snapshot?.Plan ?? new Plan(),
                    Limits = new List<UsageLimit>(),
                    Activity = activity,
                    Status = SnapshotStatus.SignedOut,
                });
                return;
            }

            if (credentials.IsExpired)
            {
                Commit(Keep(activity, SnapshotStatus.Expired));
                return;
            }

            try
            {
                var usage = await ClaudeApi.Usage(credentials.AccessToken, cancel).ConfigureAwait(false);
                ProfileResponse? profile = null;
                try
                {
                    profile = await ClaudeApi.Profile(credentials.AccessToken, cancel).ConfigureAwait(false);
                }
                catch (ClaudeApiException)
                {
                    // The plan name is a nice to have, the limits matter more.
                }

                Commit(new UsageSnapshot
                {
                    UpdatedAt = DateTimeOffset.Now,
                    Plan = PlanDetector.Detect(profile, credentials),
                    Limits = usage?.UsageLimits() ?? new List<UsageLimit>(),
                    ExtraUsage = usage?.ExtraSpend(),
                    Activity = activity,
                    Status = SnapshotStatus.Ok,
                });
            }
            catch (ClaudeApiException exception)
            {
                Commit(Keep(activity, exception.IsUnauthorized ? SnapshotStatus.Expired : SnapshotStatus.Offline));
            }
            catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException)
            {
                Commit(Keep(activity, SnapshotStatus.Offline));
            }
        }
        finally
        {
            gate.Release();
        }
    }

    /// Keeps the last numbers we had and just marks why they are not fresh.
    private UsageSnapshot Keep(ActivityLog? activity, SnapshotStatus status) => new()
    {
        UpdatedAt = Snapshot?.UpdatedAt ?? DateTimeOffset.Now,
        Plan = Snapshot?.Plan ?? new Plan(),
        Limits = Snapshot?.Limits ?? new List<UsageLimit>(),
        ExtraUsage = Snapshot?.ExtraUsage,
        Activity = activity ?? Snapshot?.Activity,
        Status = status,
    };

    private void Commit(UsageSnapshot snapshot)
    {
        Snapshot = snapshot;
        Save(snapshot);
        Updated?.Invoke(snapshot);
    }

    private static void Save(UsageSnapshot snapshot)
    {
        try
        {
            Directory.CreateDirectory(Settings.Folder);
            File.WriteAllText(SnapshotPath, JsonSerializer.Serialize(snapshot));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
        }
    }

    private static UsageSnapshot? LoadCached()
    {
        try
        {
            return File.Exists(SnapshotPath)
                ? JsonSerializer.Deserialize<UsageSnapshot>(File.ReadAllText(SnapshotPath))
                : null;
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs args)
    {
        if (args.Mode == PowerModes.Resume) _ = Refresh();
    }

    public void Dispose()
    {
        SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        timer.Stop();
        timer.Dispose();
        // A refresh may still be finishing, and it releases the gate on its way out.
    }
}
