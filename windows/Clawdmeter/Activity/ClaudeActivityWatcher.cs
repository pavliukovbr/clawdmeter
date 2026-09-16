using System.IO;
using System.Text;
using System.Text.Json;
using Clawdmeter.Usage;

namespace Clawdmeter.Activity;

public enum PetActivity { Idle, Thinking, Typing, Reading, Searching, Building, Celebrating, Sleeping }

public enum EasterEggKind { WebSlinger, PopStar }

public sealed record EasterEgg(EasterEggKind Kind, DateTimeOffset Date);

public sealed record ActivityEvent(PetActivity Activity, DateTimeOffset Date, string? Project);

/// Watches the session logs Claude Code writes under the user folder and works out what
/// Claude is doing right now. Only tool names, turn ends and the two easter egg phrases
/// are looked at, and nothing is ever written back or sent anywhere.
public sealed class ClaudeActivityWatcher : IDisposable
{
    private readonly FileSystemWatcher? watcher;
    private readonly System.Timers.Timer poll = new(5000);
    /// Claude Code appends to its log many times a turn, so wait for the writing to settle.
    private readonly System.Timers.Timer settle = new(700) { AutoReset = false };
    private readonly object gate = new();
    private string? newestFile;
    private DateTime newestWriteTime;

    public static string ProjectsFolder => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".claude",
        "projects");

    public ActivityEvent? Latest { get; private set; }
    public FinishedTurn? LastFinishedTurn { get; private set; }
    public EasterEgg? LatestEasterEgg { get; private set; }

    public event Action<ActivityEvent>? ActivityChanged;
    public event Action<FinishedTurn>? TurnFinished;
    public event Action<EasterEgg>? EasterEggSpotted;

    public ClaudeActivityWatcher()
    {
        if (Directory.Exists(ProjectsFolder))
        {
            watcher = new FileSystemWatcher(ProjectsFolder, "*.jsonl")
            {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName,
                InternalBufferSize = 64 * 1024,
            };
            watcher.Changed += (_, _) => Schedule();
            watcher.Created += (_, _) => Schedule();
            watcher.Error += (_, _) => Schedule();
            watcher.EnableRaisingEvents = true;
        }
        settle.Elapsed += (_, _) => Scan();
        poll.Elapsed += (_, _) => Scan();
        poll.AutoReset = true;
        poll.Start();
        Scan();
    }

    /// True when Claude wrote something in the last few seconds.
    public bool IsClaudeWorking(TimeSpan within)
    {
        var latest = Latest;
        if (latest is null) return false;
        if (latest.Activity is PetActivity.Idle or PetActivity.Celebrating or PetActivity.Sleeping) return false;
        return DateTimeOffset.Now - latest.Date < within;
    }

    private void Schedule()
    {
        settle.Stop();
        settle.Start();
    }

    private void Scan()
    {
        lock (gate)
        {
            try
            {
                ScanLocked();
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
            {
            }
        }
    }

    private void ScanLocked()
    {
        if (!Directory.Exists(ProjectsFolder)) return;
        var newest = new DirectoryInfo(ProjectsFolder)
            .EnumerateFiles("*.jsonl", SearchOption.AllDirectories)
            .Where(file => DateTime.UtcNow - file.LastWriteTimeUtc < TimeSpan.FromHours(6))
            .MaxBy(file => file.LastWriteTimeUtc);
        if (newest is null) return;
        if (newest.FullName == newestFile && newest.LastWriteTimeUtc == newestWriteTime) return;
        newestFile = newest.FullName;
        newestWriteTime = newest.LastWriteTimeUtc;
        ReadTail(newest);
    }

    /// Reads the end of the newest log: the last tool Claude used, whether the turn ended,
    /// and the prompt that started it.
    private void ReadTail(FileInfo file)
    {
        var text = Tail(file, 256 * 1024);
        if (text.Length == 0) return;

        var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        var project = ProjectName(file);
        PetActivity? activity = null;
        DateTimeOffset date = DateTimeOffset.Now;
        DateTimeOffset? promptDate = null;
        string? promptText = null;
        var ended = false;

        foreach (var line in lines)
        {
            if (line.Length < 2 || line[0] != '{') continue;
            JsonDocument document;
            try
            {
                document = JsonDocument.Parse(line);
            }
            catch (JsonException)
            {
                continue;
            }

            using (document)
            {
                var root = document.RootElement;
                var type = Text(root, "type");
                var stamp = ClaudeApi.ParseDate(Text(root, "timestamp")) ?? DateTimeOffset.Now;

                if (type == "user")
                {
                    var content = Raw(root, "message");
                    if (content is not null && !content.Contains("tool_result", StringComparison.Ordinal))
                    {
                        promptDate = stamp;
                        promptText = content;
                        activity = PetActivity.Thinking;
                        date = stamp;
                        ended = false;
                    }
                    continue;
                }

                if (type != "assistant") continue;
                if (!root.TryGetProperty("message", out var message)) continue;

                date = stamp;
                if (Text(message, "stop_reason") == "end_turn") ended = true;

                if (!message.TryGetProperty("content", out var content2) || content2.ValueKind != JsonValueKind.Array) continue;
                foreach (var block in content2.EnumerateArray())
                {
                    var blockType = Text(block, "type");
                    if (blockType == "tool_use")
                    {
                        activity = ToolActivity(Text(block, "name"));
                        ended = false;
                    }
                    else if (blockType == "text")
                    {
                        activity ??= PetActivity.Typing;
                    }
                }
            }
        }

        if (ended)
        {
            var turn = new FinishedTurn
            {
                Date = date,
                Duration = promptDate is { } start ? (date - start).TotalSeconds : null,
                Project = project,
            };
            LastFinishedTurn = turn;
            activity = PetActivity.Celebrating;
            TurnFinished?.Invoke(turn);
        }

        if (activity is { } next)
        {
            var current = new ActivityEvent(next, date, project);
            if (Latest?.Activity != next || Latest?.Date != date)
            {
                Latest = current;
                ActivityChanged?.Invoke(current);
            }
        }

        if (promptText is not null && promptDate is { } when && EggIn(promptText) is { } kind)
        {
            if (LatestEasterEgg?.Date != when)
            {
                var egg = new EasterEgg(kind, when);
                LatestEasterEgg = egg;
                EasterEggSpotted?.Invoke(egg);
            }
        }
    }

    private static PetActivity ToolActivity(string? tool) => tool switch
    {
        "WebSearch" or "WebFetch" => PetActivity.Searching,
        "Read" or "NotebookRead" or "Glob" or "Grep" => PetActivity.Reading,
        "Edit" or "Write" or "NotebookEdit" or "MultiEdit" => PetActivity.Building,
        "Bash" or "BashOutput" => PetActivity.Building,
        null => PetActivity.Thinking,
        _ => PetActivity.Thinking,
    };

    /// The two phrases Clawd listens for, checked only in what you type to Claude.
    private static EasterEggKind? EggIn(string text)
    {
        var squashed = text.ToLowerInvariant().Replace("-", "").Replace(" ", "");
        if (squashed.Contains("spiderman") || squashed.Contains("homemaranha")) return EasterEggKind.WebSlinger;
        if (squashed.Contains("ladygaga")) return EasterEggKind.PopStar;
        return null;
    }

    private static string ProjectName(FileInfo file)
    {
        var folder = file.Directory?.Name ?? "";
        var parts = folder.Split('-', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length > 0 ? parts[^1] : "project";
    }

    private static string Tail(FileInfo file, int bytes)
    {
        using var stream = new FileStream(file.FullName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        var length = stream.Length;
        var start = Math.Max(0, length - bytes);
        stream.Seek(start, SeekOrigin.Begin);
        var buffer = new byte[length - start];
        var read = stream.Read(buffer, 0, buffer.Length);
        var text = Encoding.UTF8.GetString(buffer, 0, read);
        // The first line may be cut in half by the window, so drop it.
        var newline = text.IndexOf('\n');
        return start > 0 && newline >= 0 ? text[(newline + 1)..] : text;
    }

    private static string? Text(JsonElement element, string name)
        => element.ValueKind == JsonValueKind.Object
           && element.TryGetProperty(name, out var value)
           && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static string? Raw(JsonElement element, string name)
        => element.TryGetProperty(name, out var value) ? value.GetRawText() : null;

    public void Dispose()
    {
        watcher?.Dispose();
        settle.Dispose();
        poll.Dispose();
    }
}
