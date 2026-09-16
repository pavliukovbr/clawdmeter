using System.Text.Json.Serialization;

namespace Clawdmeter.Usage;

public enum PlanKind { Free, Pro, Max, Team, Enterprise, Api, Unknown }

public enum LimitKind { Session, Weekly, Model, Other }

public enum Severity { Normal, Warning, Critical }

public enum SnapshotStatus { Ok, Offline, Expired, SignedOut }

public enum ClawdMood { Idle, Busy, Tired, Sleeping, Happy }

public sealed class Plan
{
    public PlanKind Kind { get; set; } = PlanKind.Unknown;
    public string? Tier { get; set; }

    [JsonIgnore]
    public string Name => Kind switch
    {
        PlanKind.Free => "Free",
        PlanKind.Pro => "Pro",
        PlanKind.Max => Tier is null ? "Max" : $"Max {Tier}",
        PlanKind.Team => Tier is null ? "Team" : $"Team {Tier}",
        PlanKind.Enterprise => "Enterprise",
        PlanKind.Api => "API",
        _ => "Claude",
    };

    [JsonIgnore]
    public bool HasPlanLimits => Kind != PlanKind.Api;
}

public sealed class UsageLimit
{
    public string Id { get; set; } = "";
    public LimitKind Kind { get; set; }
    public string Title { get; set; } = "";
    public double Percent { get; set; }
    public DateTimeOffset? ResetsAt { get; set; }
    public Severity Severity { get; set; }

    /// Once the window has rolled over the usage starts again from zero.
    public double PercentAt(DateTimeOffset date)
    {
        if (ResetsAt is { } reset && reset <= date) return 0;
        return Math.Clamp(Percent, 0, 100);
    }

    public Severity SeverityAt(DateTimeOffset date)
    {
        if (ResetsAt is { } reset && reset <= date) return Severity.Normal;
        if (Severity != Severity.Normal) return Severity;
        return Percent switch
        {
            >= 90 => Severity.Critical,
            >= 75 => Severity.Warning,
            _ => Severity.Normal,
        };
    }
}

public sealed class ExtraUsage
{
    public double Used { get; set; }
    public double? Limit { get; set; }
    public string CurrencyCode { get; set; } = "USD";

    [JsonIgnore]
    public double? Percent => Limit is > 0 ? Math.Min(Used / Limit.Value * 100, 100) : null;
}

public sealed class ActivityDay
{
    public DateTimeOffset Date { get; set; }
    public long Tokens { get; set; }
    public int Messages { get; set; }
}

public sealed class ActivityLog
{
    public List<ActivityDay> Days { get; set; } = new();
    public DateTimeOffset? LastActiveAt { get; set; }

    [JsonIgnore]
    public ActivityDay? Today
    {
        get
        {
            var last = Days.Count > 0 ? Days[^1] : null;
            return last is not null && last.Date.Date == DateTimeOffset.Now.Date ? last : null;
        }
    }

    [JsonIgnore]
    public long TodayTokens => Today?.Tokens ?? 0;

    [JsonIgnore]
    public int TodayMessages => Today?.Messages ?? 0;
}

public sealed class UsageSnapshot
{
    public DateTimeOffset UpdatedAt { get; set; }
    public Plan Plan { get; set; } = new();
    public List<UsageLimit> Limits { get; set; } = new();
    public ExtraUsage? ExtraUsage { get; set; }
    public ActivityLog? Activity { get; set; }
    public SnapshotStatus Status { get; set; }

    [JsonIgnore]
    public UsageLimit? Session => Limits.FirstOrDefault(limit => limit.Kind == LimitKind.Session);

    [JsonIgnore]
    public UsageLimit? Weekly => Limits.FirstOrDefault(limit => limit.Kind == LimitKind.Weekly);
}

/// A turn of work that just ended, used for the alert and for Clawd's little cheer.
public sealed class FinishedTurn
{
    public DateTimeOffset Date { get; set; }
    public double? Duration { get; set; }
    public string? Project { get; set; }
}
