namespace Clawdmeter.Usage;

public sealed record Metric(
    string Id,
    string Title,
    string? ShortTitle,
    string Value,
    double Fraction,
    Severity Severity,
    string? Detail);

/// What the panel shows for a snapshot at a given moment, whatever the plan.
public sealed class UsageSummary
{
    public string PlanName { get; }
    public Metric Primary { get; }
    public IReadOnlyList<Metric> Secondary { get; }
    public ClawdMood Mood { get; }
    public ActivityLog? Activity { get; }
    public string? Note { get; }
    public bool HasData { get; }

    public UsageSummary(UsageSnapshot? snapshot, DateTimeOffset date)
    {
        if (snapshot is null)
        {
            PlanName = "Clawdmeter";
            Primary = new Metric("empty", "Waiting for data", null, "Hi!", 0, Severity.Normal, null);
            Secondary = Array.Empty<Metric>();
            Mood = ClawdMood.Sleeping;
            Note = "Sign in to Claude Code to start";
            HasData = false;
            return;
        }

        PlanName = snapshot.Plan.Name;
        Activity = snapshot.Activity;
        HasData = true;

        var metrics = snapshot.Limits.Select(limit => MetricFor(limit, date)).ToList();
        if (snapshot.ExtraUsage is { } extra) metrics.Add(MetricFor(extra));

        if (metrics.Count > 0)
        {
            Primary = metrics[0];
            Secondary = metrics.Skip(1).ToList();
        }
        else
        {
            Primary = TokenMetric(snapshot.Activity);
            Secondary = Array.Empty<Metric>();
        }

        Mood = MoodFor(snapshot, date);
        Note = NoteFor(snapshot, date);
    }

    private static Metric MetricFor(UsageLimit limit, DateTimeOffset date)
    {
        var percent = limit.PercentAt(date);
        string? detail = null;
        if (limit.ResetsAt is { } reset)
        {
            detail = reset > date ? Format.Reset(reset, date) : "Fresh window";
        }
        return new Metric(limit.Id, limit.Title, null, Format.Percent(percent), percent / 100, limit.SeverityAt(date), detail);
    }

    private static Metric MetricFor(ExtraUsage extra)
    {
        var used = Format.Money(extra.Used, extra.CurrencyCode);
        if (extra.Percent is not { } percent || extra.Limit is not { } limit)
        {
            return new Metric("extra", "Extra usage", "Extra", used, 0, Severity.Normal, "No monthly cap");
        }
        var severity = percent >= 90 ? Severity.Critical : percent >= 75 ? Severity.Warning : Severity.Normal;
        return new Metric(
            "extra",
            "Extra usage",
            "Extra",
            Format.Percent(percent),
            percent / 100,
            severity,
            $"{used} of {Format.Money(limit, extra.CurrencyCode)}");
    }

    private static Metric TokenMetric(ActivityLog? activity)
    {
        var today = activity?.TodayTokens ?? 0;
        var busiest = activity?.Days.Select(day => day.Tokens).DefaultIfEmpty(0).Max() ?? 0;
        return new Metric(
            "tokens",
            "Tokens today",
            null,
            Format.Tokens(today),
            busiest > 0 ? (double)today / busiest : 0,
            Severity.Normal,
            activity is null ? null : $"{activity.TodayMessages} requests");
    }

    private static ClawdMood MoodFor(UsageSnapshot snapshot, DateTimeOffset date)
    {
        var sinceActive = snapshot.Activity?.LastActiveAt is { } active
            ? (date - active).TotalSeconds
            : double.PositiveInfinity;
        var workingNow = sinceActive < 3 * 60;

        if (snapshot.Session is not { } session)
        {
            if (workingNow) return ClawdMood.Busy;
            return sinceActive > 30 * 60 ? ClawdMood.Sleeping : ClawdMood.Idle;
        }

        var percent = session.PercentAt(date);
        var weekly = snapshot.Weekly?.PercentAt(date) ?? 0;
        if (percent >= 100) return ClawdMood.Sleeping;
        if (percent >= 80 || weekly >= 90) return ClawdMood.Tired;
        if (percent >= 50 || weekly >= 75 || workingNow) return ClawdMood.Busy;

        var windowOpen = session.ResetsAt is { } reset && reset > date;
        if (!windowOpen && sinceActive > 30 * 60) return ClawdMood.Sleeping;
        return ClawdMood.Idle;
    }

    private static string? NoteFor(UsageSnapshot snapshot, DateTimeOffset date)
    {
        switch (snapshot.Status)
        {
            case SnapshotStatus.SignedOut:
                return "Sign in to Claude Code";
            case SnapshotStatus.Expired:
                return "Open Claude Code to reconnect";
            case SnapshotStatus.Offline when (date - snapshot.UpdatedAt).TotalMinutes > 15:
                return $"Updated {Format.Relative(snapshot.UpdatedAt, date)}";
            default:
                if ((date - snapshot.UpdatedAt).TotalMinutes > 45)
                {
                    return $"Updated {Format.Relative(snapshot.UpdatedAt, date)}";
                }
                return null;
        }
    }
}
