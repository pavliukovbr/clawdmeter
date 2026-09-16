using System.IO;
using System.Text;
using System.Text.Json;

namespace Clawdmeter.Usage;

/// Adds up tokens from the session logs Claude Code keeps under the user folder.
/// Files are read incrementally, so a refresh only parses lines written since the last one.
public sealed class ActivityScanner
{
    private sealed record Record(DateTimeOffset Date, long Tokens);

    private readonly Dictionary<string, long> offsets = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Record> records = new(StringComparer.Ordinal);
    private DateTimeOffset? lastActiveAt;

    private static readonly string[] TokenFields =
    {
        "input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
    };

    public ActivityLog? Scan(DateTimeOffset now)
    {
        var root = Activity.ClaudeActivityWatcher.ProjectsFolder;
        if (!Directory.Exists(root)) return null;

        var today = new DateTimeOffset(now.Date, now.Offset);
        var windowStart = today.AddDays(-6);
        var found = false;

        foreach (var path in Directory.EnumerateFiles(root, "*.jsonl", SearchOption.AllDirectories))
        {
            found = true;
            FileInfo file;
            try
            {
                file = new FileInfo(path);
                if (file.LastWriteTimeUtc < windowStart.UtcDateTime) continue;
            }
            catch (IOException)
            {
                continue;
            }

            offsets.TryGetValue(path, out var offset);
            if (file.Length < offset) offset = 0;
            if (file.Length <= offset) continue;
            offsets[path] = Read(file, offset, windowStart);
        }

        if (!found) return null;

        foreach (var key in records.Where(pair => pair.Value.Date < windowStart).Select(pair => pair.Key).ToList())
        {
            records.Remove(key);
        }

        var days = Enumerable.Range(0, 7)
            .Select(index => new ActivityDay { Date = windowStart.AddDays(index) })
            .ToList();
        foreach (var record in records.Values)
        {
            var index = (int)(record.Date.Date - windowStart.Date).TotalDays;
            if (index < 0 || index >= days.Count) continue;
            days[index].Tokens += record.Tokens;
            days[index].Messages += 1;
        }
        return new ActivityLog { Days = days, LastActiveAt = lastActiveAt };
    }

    private long Read(FileInfo file, long offset, DateTimeOffset windowStart)
    {
        try
        {
            using var stream = new FileStream(file.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            stream.Seek(offset, SeekOrigin.Begin);
            var buffer = new byte[stream.Length - offset];
            var read = stream.Read(buffer, 0, buffer.Length);
            var lastNewline = Array.LastIndexOf(buffer, (byte)'\n', Math.Max(read - 1, 0));
            if (lastNewline < 0) return offset;

            // Stop at the last full line, the one after it may still be getting written.
            var text = Encoding.UTF8.GetString(buffer, 0, lastNewline + 1);
            foreach (var line in text.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.Contains("\"usage\"", StringComparison.Ordinal)) Ingest(line, windowStart);
            }
            return offset + lastNewline + 1;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return offset;
        }
    }

    private void Ingest(string line, DateTimeOffset windowStart)
    {
        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return;
            if (Text(root, "type") != "assistant") return;
            if (!root.TryGetProperty("message", out var message)) return;
            if (!message.TryGetProperty("usage", out var usage)) return;
            if (ClaudeApi.ParseDate(Text(root, "timestamp")) is not { } timestamp) return;

            if (timestamp > (lastActiveAt ?? DateTimeOffset.MinValue)) lastActiveAt = timestamp;
            if (timestamp < windowStart) return;

            // Streaming writes the same reply more than once, and resumed sessions copy
            // history into new files, so count each request once.
            var messageId = Text(message, "id") ?? Guid.NewGuid().ToString();
            var requestId = Text(root, "requestId") ?? "";
            long tokens = 0;
            foreach (var field in TokenFields)
            {
                if (usage.TryGetProperty(field, out var value) && value.TryGetInt64(out var count)) tokens += count;
            }
            records[messageId + requestId] = new Record(timestamp, tokens);
        }
        catch (JsonException)
        {
        }
    }

    private static string? Text(JsonElement element, string name)
        => element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
