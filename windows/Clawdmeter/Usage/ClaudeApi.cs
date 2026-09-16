using System.IO;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Clawdmeter.Usage;

public sealed class ClaudeCredentials
{
    public string AccessToken { get; init; } = "";
    public DateTimeOffset? ExpiresAt { get; init; }
    public string? SubscriptionType { get; init; }
    public string? RateLimitTier { get; init; }

    public bool IsExpired => ExpiresAt is { } expires && expires < DateTimeOffset.Now.AddMinutes(1);
}

/// Reads the sign in that Claude Code already stores on this PC.
/// The token stays in memory and is only ever sent to api.anthropic.com.
public static class CredentialsReader
{
    public static ClaudeCredentials? Read()
    {
        foreach (var path in Paths())
        {
            try
            {
                if (!File.Exists(path)) continue;
                var credentials = Parse(File.ReadAllText(path));
                if (credentials is not null) return credentials;
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
            {
            }
        }
        return FromCredentialManager();
    }

    private static IEnumerable<string> Paths()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        yield return Path.Combine(home, ".claude", ".credentials.json");
        yield return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Claude",
            ".credentials.json");
        yield return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Claude",
            ".credentials.json");
    }

    /// On Windows, Claude Code keeps the sign in in the credential manager rather than a file.
    private static ClaudeCredentials? FromCredentialManager()
    {
        foreach (var target in new[] { "Claude Code-credentials", "Claude Code", "claude-code-credentials" })
        {
            if (ReadCredential(target) is { } found) return found;
        }

        foreach (var target in CredentialNames())
        {
            if (!target.Contains("claude", StringComparison.OrdinalIgnoreCase)) continue;
            if (ReadCredential(target) is { } found) return found;
        }
        return null;
    }

    private static ClaudeCredentials? ReadCredential(string target)
    {
        if (!CredRead(target, CredentialTypeGeneric, 0, out var handle)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(handle);
            if (credential.CredentialBlobSize == 0 || credential.CredentialBlob == 0) return null;
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Parse(Decode(bytes));
        }
        catch (Exception exception) when (exception is JsonException or ArgumentException)
        {
            return null;
        }
        finally
        {
            CredFree(handle);
        }
    }

    /// Only the names are looked at, and only the ones that mention Claude are opened.
    private static IEnumerable<string> CredentialNames()
    {
        if (!CredEnumerate(null, 0, out var count, out var array)) yield break;
        var names = new List<string>();
        try
        {
            for (var index = 0; index < count; index++)
            {
                var entry = Marshal.ReadIntPtr(array, index * nint.Size);
                var credential = Marshal.PtrToStructure<Credential>(entry);
                if (credential.TargetName == 0) continue;
                var name = Marshal.PtrToStringUni(credential.TargetName);
                if (name is not null) names.Add(name);
            }
        }
        finally
        {
            CredFree(array);
        }
        foreach (var name in names) yield return name;
    }

    /// The blob is written as plain text by some versions and as wide text by others.
    private static string Decode(byte[] bytes)
    {
        var text = System.Text.Encoding.UTF8.GetString(bytes).TrimStart('﻿');
        if (text.TrimStart().StartsWith('{')) return text;
        return System.Text.Encoding.Unicode.GetString(bytes).TrimStart('﻿');
    }

    private const uint CredentialTypeGeneric = 1;

    [StructLayout(LayoutKind.Sequential)]
    private struct Credential
    {
        public uint Flags;
        public uint Type;
        public nint TargetName;
        public nint Comment;
        public long LastWritten;
        public uint CredentialBlobSize;
        public nint CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public nint Attributes;
        public nint TargetAlias;
        public nint UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint flags, out nint credential);

    [DllImport("advapi32.dll", EntryPoint = "CredEnumerateW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredEnumerate(string? filter, uint flags, out int count, out nint credentials);

    [DllImport("advapi32.dll", EntryPoint = "CredFree")]
    private static extern void CredFree(nint buffer);

    private static ClaudeCredentials? Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("claudeAiOauth", out var oauth)) return null;
        if (!oauth.TryGetProperty("accessToken", out var tokenElement)) return null;
        var token = tokenElement.GetString();
        if (string.IsNullOrEmpty(token)) return null;

        DateTimeOffset? expires = null;
        if (oauth.TryGetProperty("expiresAt", out var expiresElement) && expiresElement.TryGetDouble(out var milliseconds))
        {
            expires = DateTimeOffset.FromUnixTimeMilliseconds((long)milliseconds);
        }

        return new ClaudeCredentials
        {
            AccessToken = token,
            ExpiresAt = expires,
            SubscriptionType = Text(oauth, "subscriptionType"),
            RateLimitTier = Text(oauth, "rateLimitTier"),
        };
    }

    private static string? Text(JsonElement element, string name)
        => element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}

public sealed class ClaudeApiException(int status) : Exception($"Claude API answered {status}")
{
    public int Status { get; } = status;
    public bool IsUnauthorized => Status is 401 or 403;
}

public static class ClaudeApi
{
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(20) };

    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true,
        Converters = { new FlexibleDateConverter() },
    };

    public static Task<UsageResponse?> Usage(string token, CancellationToken cancel = default)
        => Get<UsageResponse>("usage", token, cancel);

    public static Task<ProfileResponse?> Profile(string token, CancellationToken cancel = default)
        => Get<ProfileResponse>("profile", token, cancel);

    private static async Task<T?> Get<T>(string path, string token, CancellationToken cancel)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.anthropic.com/api/oauth/" + path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Add("anthropic-beta", "oauth-2025-04-20");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        using var response = await Client.SendAsync(request, cancel).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode) throw new ClaudeApiException((int)response.StatusCode);
        var stream = await response.Content.ReadAsStreamAsync(cancel).ConfigureAwait(false);
        return await JsonSerializer.DeserializeAsync<T>(stream, Options, cancel).ConfigureAwait(false);
    }

    /// The API sends microseconds, which the plain parser does not always accept, so drop them.
    public static DateTimeOffset? ParseDate(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        if (DateTimeOffset.TryParse(text, null, System.Globalization.DateTimeStyles.RoundtripKind, out var date)) return date;
        var trimmed = Regex.Replace(text, @"\.\d+", "");
        return DateTimeOffset.TryParse(trimmed, null, System.Globalization.DateTimeStyles.RoundtripKind, out date) ? date : null;
    }
}

public sealed class FlexibleDateConverter : JsonConverter<DateTimeOffset?>
{
    public override DateTimeOffset? Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null) return null;
        if (reader.TokenType == JsonTokenType.Number) return DateTimeOffset.FromUnixTimeSeconds(reader.GetInt64());
        return ClaudeApi.ParseDate(reader.GetString());
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset? value, JsonSerializerOptions options)
    {
        if (value is { } date) writer.WriteStringValue(date); else writer.WriteNullValue();
    }
}

// MARK: Responses

public sealed class UsageResponse
{
    public sealed class Window
    {
        public double? Utilization { get; set; }
        public DateTimeOffset? ResetsAt { get; set; }
    }

    public sealed class Named
    {
        public string? Id { get; set; }
        public string? DisplayName { get; set; }
    }

    public sealed class LimitScope
    {
        public Named? Model { get; set; }
        public Named? Surface { get; set; }
    }

    public sealed class Limit
    {
        public string? Kind { get; set; }
        public string? Group { get; set; }
        public double? Percent { get; set; }
        public string? Severity { get; set; }
        public DateTimeOffset? ResetsAt { get; set; }
        public LimitScope? Scope { get; set; }
    }

    public sealed class Extra
    {
        public bool? IsEnabled { get; set; }
        public double? MonthlyLimit { get; set; }
        public double? UsedCredits { get; set; }
        public string? Currency { get; set; }
        public int? DecimalPlaces { get; set; }
    }

    public sealed class Amount
    {
        public double? AmountMinor { get; set; }
        public string? Currency { get; set; }
        public int? Exponent { get; set; }

        public double? Value => AmountMinor is { } minor ? minor / Math.Pow(10, Exponent ?? 2) : null;
    }

    public sealed class SpendInfo
    {
        public Amount? Used { get; set; }
        public Amount? Limit { get; set; }
        public bool? Enabled { get; set; }
    }

    public Window? FiveHour { get; set; }
    public Window? SevenDay { get; set; }
    public Window? SevenDayOpus { get; set; }
    public Window? SevenDaySonnet { get; set; }
    public List<Limit>? Limits { get; set; }
    public Extra? ExtraUsage { get; set; }
    public SpendInfo? Spend { get; set; }

    public List<UsageLimit> UsageLimits()
    {
        if (Limits is { Count: > 0 })
        {
            return Limits.Select(Map).OfType<UsageLimit>().OrderBy(limit => Order(limit.Kind)).ToList();
        }

        var result = new List<UsageLimit>();
        var windows = new (Window? Window, LimitKind Kind, string Id, string Title)[]
        {
            (FiveHour, LimitKind.Session, "session", "Session"),
            (SevenDay, LimitKind.Weekly, "weekly_all", "Weekly"),
            (SevenDayOpus, LimitKind.Model, "weekly_opus", "Opus"),
            (SevenDaySonnet, LimitKind.Model, "weekly_sonnet", "Sonnet"),
        };
        foreach (var (window, kind, id, title) in windows)
        {
            if (window?.Utilization is not { } utilization) continue;
            result.Add(new UsageLimit
            {
                Id = id,
                Kind = kind,
                Title = title,
                Percent = utilization,
                ResetsAt = window.ResetsAt,
                Severity = Severity.Normal,
            });
        }
        return result;
    }

    public ExtraUsage? ExtraSpend()
    {
        if (ExtraUsage is { IsEnabled: true, UsedCredits: { } used })
        {
            var divisor = Math.Pow(10, ExtraUsage.DecimalPlaces ?? 0);
            return new ExtraUsage
            {
                Used = used / divisor,
                Limit = ExtraUsage.MonthlyLimit is { } limit ? limit / divisor : null,
                CurrencyCode = ExtraUsage.Currency ?? "USD",
            };
        }
        if (Spend is { Enabled: true } spend && spend.Used?.Value is { } value)
        {
            return new ExtraUsage
            {
                Used = value,
                Limit = spend.Limit?.Value,
                CurrencyCode = spend.Used?.Currency ?? "USD",
            };
        }
        return null;
    }

    private static UsageLimit? Map(Limit limit)
    {
        if (limit.Percent is not { } percent) return null;
        var scopeName = limit.Scope?.Model?.DisplayName ?? limit.Scope?.Surface?.DisplayName;

        LimitKind kind;
        string title;
        switch (limit.Kind)
        {
            case "session":
                kind = LimitKind.Session;
                title = "Session";
                break;
            case "weekly_all":
                kind = LimitKind.Weekly;
                title = "Weekly";
                break;
            case "weekly_scoped":
                kind = LimitKind.Model;
                title = scopeName ?? "Weekly";
                break;
            default:
                kind = limit.Group == "session" ? LimitKind.Session : LimitKind.Other;
                title = scopeName ?? Capitalized((limit.Kind ?? limit.Group ?? "Limit").Replace('_', ' '));
                break;
        }

        var id = string.Join(".", new[] { limit.Kind ?? limit.Group ?? "limit", scopeName }.Where(part => part is not null));
        return new UsageLimit
        {
            Id = id,
            Kind = kind,
            Title = title,
            Percent = percent,
            ResetsAt = limit.ResetsAt,
            Severity = limit.Severity?.ToLowerInvariant() switch
            {
                "warning" => Severity.Warning,
                "critical" => Severity.Critical,
                _ => Severity.Normal,
            },
        };
    }

    private static string Capitalized(string text)
        => string.Join(' ', text.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(word => char.ToUpperInvariant(word[0]) + word[1..]));

    private static int Order(LimitKind kind) => kind switch
    {
        LimitKind.Session => 0,
        LimitKind.Weekly => 1,
        LimitKind.Model => 2,
        _ => 3,
    };
}

public sealed class ProfileResponse
{
    public sealed class AccountInfo
    {
        public bool? HasClaudeMax { get; set; }
        public bool? HasClaudePro { get; set; }
    }

    public sealed class OrganizationInfo
    {
        public string? OrganizationType { get; set; }
        public string? RateLimitTier { get; set; }
        public string? SeatTier { get; set; }
        public string? BillingType { get; set; }
    }

    public AccountInfo? Account { get; set; }
    public OrganizationInfo? Organization { get; set; }
}

public static class PlanDetector
{
    public static Plan Detect(ProfileResponse? profile, ClaudeCredentials credentials)
    {
        var organization = profile?.Organization;
        var type = (organization?.OrganizationType ?? "").ToLowerInvariant();
        var tier = (organization?.RateLimitTier ?? credentials.RateLimitTier ?? "").ToLowerInvariant();
        var subscription = (credentials.SubscriptionType ?? "").ToLowerInvariant();
        var hints = new[] { type, subscription };

        if (hints.Any(hint => hint.Contains("enterprise"))) return new Plan { Kind = PlanKind.Enterprise };
        if (hints.Any(hint => hint.Contains("team"))) return new Plan { Kind = PlanKind.Team, Tier = SeatName(organization?.SeatTier) };
        if (hints.Any(hint => hint.Contains("max")) || tier.Contains("max") || profile?.Account?.HasClaudeMax == true)
        {
            return new Plan { Kind = PlanKind.Max, Tier = Multiplier(tier) };
        }
        if (hints.Any(hint => hint.Contains("pro")) || tier.Contains("pro") || profile?.Account?.HasClaudePro == true)
        {
            return new Plan { Kind = PlanKind.Pro };
        }
        if (hints.Any(hint => hint.Contains("free")) || tier.Contains("free")) return new Plan { Kind = PlanKind.Free };
        if (type.Contains("api") || type.Contains("console")) return new Plan { Kind = PlanKind.Api };
        return new Plan { Kind = type.Length == 0 && subscription.Length == 0 ? PlanKind.Unknown : PlanKind.Free };
    }

    /// "default_claude_max_20x" becomes "20x".
    private static string? Multiplier(string tier)
    {
        var match = Regex.Match(tier, @"\d+x");
        return match.Success ? match.Value[..^1] + "×" : null;
    }

    /// Premium seats get a label, standard seats are just Team.
    private static string? SeatName(string? seat)
        => seat?.ToLowerInvariant().Contains("premium") == true ? "Premium" : null;
}
