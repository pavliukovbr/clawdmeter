using System.Globalization;

namespace Clawdmeter.Usage;

public static class Format
{
    public static string Percent(double value) => $"{Math.Round(value)}%";

    /// Compact time left, like "45m", "2h 13m" or "3d 4h".
    public static string Countdown(DateTimeOffset date, DateTimeOffset now)
    {
        var minutes = (int)Math.Ceiling((date - now).TotalMinutes);
        if (minutes <= 0) return "now";
        if (minutes < 60) return $"{minutes}m";
        var hours = minutes / 60;
        if (hours < 24)
        {
            var rest = minutes % 60;
            return rest == 0 ? $"{hours}h" : $"{hours}h {rest}m";
        }
        var days = hours / 24;
        var hoursLeft = hours % 24;
        return hoursLeft == 0 ? $"{days}d" : $"{days}d {hoursLeft}h";
    }

    /// "Mon 02:00" for far away resets, a countdown when it is close.
    public static string Reset(DateTimeOffset date, DateTimeOffset now)
    {
        if ((date - now).TotalHours < 24) return $"Resets in {Countdown(date, now)}";
        return "Resets " + date.ToLocalTime().ToString("ddd HH:mm", CultureInfo.CurrentCulture);
    }

    public static string Tokens(long value)
    {
        double number = value;
        if (value >= 1_000_000_000) return Trimmed(number / 1_000_000_000) + "B";
        if (value >= 1_000_000) return Trimmed(number / 1_000_000) + "M";
        if (value >= 10_000) return $"{(int)(number / 1000)}K";
        if (value >= 1_000) return Trimmed(number / 1000) + "K";
        return value.ToString(CultureInfo.CurrentCulture);
    }

    public static string Money(double value, string currencyCode)
    {
        var symbol = currencyCode.ToUpperInvariant() switch
        {
            "USD" => "$",
            "EUR" => "€",
            "GBP" => "£",
            "BRL" => "R$",
            _ => currencyCode.ToUpperInvariant() + " ",
        };
        var text = value < 100
            ? value.ToString("0.00", CultureInfo.InvariantCulture)
            : value.ToString("0", CultureInfo.InvariantCulture);
        return symbol + text;
    }

    /// How long something took, like "45s", "4m 12s" or "1h 5m".
    public static string Duration(double seconds)
    {
        var total = (int)Math.Round(seconds);
        if (total < 60) return $"{total}s";
        var minutes = total / 60;
        if (minutes < 60)
        {
            var rest = total % 60;
            return rest == 0 ? $"{minutes}m" : $"{minutes}m {rest}s";
        }
        var restMinutes = minutes % 60;
        return restMinutes == 0 ? $"{minutes / 60}h" : $"{minutes / 60}h {restMinutes}m";
    }

    /// "Done in my-project after 4m 12s."
    public static string Finished(FinishedTurn turn)
    {
        var text = turn.Project is null ? "Done" : $"Done in {turn.Project}";
        if (turn.Duration is { } duration) text += $" after {Duration(duration)}";
        return text + ".";
    }

    public static string Relative(DateTimeOffset date, DateTimeOffset now)
    {
        if ((now - date).TotalSeconds < 60) return "just now";
        return $"{Countdown(now, date)} ago";
    }

    private static string Trimmed(double value)
    {
        var text = value < 10
            ? value.ToString("0.0", CultureInfo.InvariantCulture)
            : value.ToString("0", CultureInfo.InvariantCulture);
        return text.EndsWith(".0", StringComparison.Ordinal) ? text[..^2] : text;
    }
}
